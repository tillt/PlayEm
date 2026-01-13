//
//  NSString+Sanitized.m
//  PlayEm
//
//  Created by Till Toenshoff on 12/27/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#include <stdlib.h>

#import "NSString+Sanitized.h"

// Bounding extremely long or corrupt strings keeps the sanitizer from doing
// heavy work (or appearing to hang) on pathological mojibake payloads.
static const NSUInteger kCFMaxScanCharacters = 4096;
static const NSUInteger kCFMaxStringLength = 4096;
// Enable verbose logging for debugging; compile-time gated by DEBUG_SANITIZER.
static void cf_logStage(NSString* label, NSString* value);

static NSString* cf_hexUTF8(NSString* s)
{
    NSData* utf8 = [s dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    const uint8_t* p = utf8.bytes;
    NSMutableString* hex = [NSMutableString stringWithCapacity:utf8.length * 3];
    for (NSUInteger i = 0; i < utf8.length; i++) {
        [hex appendFormat:@"%02X", p[i]];
        if (i + 1 < utf8.length)
            [hex appendString:@" "];
    }
    return hex;
}

static NSInteger cf_replacementCount(NSString* s)
{
    __block NSInteger count = 0;

    NSUInteger len = MIN(s.length, kCFMaxScanCharacters);

    // Ugly a.f.!
    [s enumerateSubstringsInRange:NSMakeRange(0, len)
                          options:NSStringEnumerationByComposedCharacterSequences
                       usingBlock:^(NSString* substring, NSRange __, NSRange ___, BOOL* stop) {
                           if ([substring characterAtIndex:0] == 0xFFFD) {
                               count++;
                               // Avoid spending excessive time on garbage input.
                               if (count > 512) {
                                   *stop = YES;
                               }
                           }
                       }];
    return count;
}

// Lower score is better.
static NSInteger cf_mojibakeScore(NSString* s)
{
    __block NSInteger bad = cf_replacementCount(s);
    // Markers commonly seen in Latin/CP1252 mojibake and some Cyrillic mangling.
    NSCharacterSet* markers = [NSCharacterSet characterSetWithCharactersInString:@"ÃÂðÐÑ"];
    // Additional suspicious glyphs that often indicate mojibake (e.g., √® for é).
    NSCharacterSet* suspicious = [NSCharacterSet characterSetWithCharactersInString:@"\u221A\u00AE"];
    NSUInteger len = MIN(s.length, kCFMaxScanCharacters);
    [s enumerateSubstringsInRange:NSMakeRange(0, len)
                          options:NSStringEnumerationByComposedCharacterSequences
                       usingBlock:^(NSString* substring, NSRange __, NSRange ___, BOOL* stop) {
                           if ([markers characterIsMember:[substring characterAtIndex:0]]) {
                               bad++;
                           } else if ([suspicious characterIsMember:[substring characterAtIndex:0]]) {
                               bad += 2;  // heavier penalty to steer scoring away from
                                          // mojibake like √®
                           }
                       }];
    if ([s rangeOfString:@"\u221A\u00AE"].location != NSNotFound) {
        bad += 3;  // penalize the √® pair specifically.
    }
    return bad;
}

static NSString* cf_normalize(NSString* s)
{
    if (s == nil) {
        return @"";
    }
    // Trim pathological strings before processing.
    if (s.length > kCFMaxStringLength) {
        s = [s substringToIndex:kCFMaxStringLength];
    }
    NSMutableString* m = [[s precomposedStringWithCanonicalMapping] mutableCopy];
    [m replaceOccurrencesOfString:@"\u00A0" withString:@" " options:0 range:NSMakeRange(0, m.length)];

    static NSRegularExpression* wsRE;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        wsRE = [NSRegularExpression regularExpressionWithPattern:@"\\s+" options:0 error:nil];
    });
    NSString* collapsed = [wsRE stringByReplacingMatchesInString:m options:0 range:NSMakeRange(0, m.length) withTemplate:@" "];
    return [collapsed stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

// Reinterpret the string's bytes from one encoding to another, then normalize.
static NSString* cf_reinterpret(NSString* s, NSStringEncoding fromEnc, NSStringEncoding toEnc)
{
    NSData* data = [s dataUsingEncoding:fromEnc allowLossyConversion:NO];
    if (data.length == 0)
        return nil;
    NSString* out = [[NSString alloc] initWithData:data encoding:toEnc];
    if (!out)
        return nil;
    return cf_normalize(out);
}

// Heuristic: compute an accent priority for a string. Lower is better.
// Acute accents (U+0301) rank higher than grave (U+0300); others are neutral.
static NSInteger cf_accentPriority(NSString* s)
{
    __block NSInteger priority = 1;  // neutral
    [s enumerateSubstringsInRange:NSMakeRange(0, s.length)
                          options:NSStringEnumerationByComposedCharacterSequences
                       usingBlock:^(NSString* substring, NSRange __, NSRange ___, BOOL* stop) {
                           NSString* decomposed = [substring decomposedStringWithCanonicalMapping];
                           for (NSUInteger i = 0; i < decomposed.length; i++) {
                               unichar c = [decomposed characterAtIndex:i];
                               if (c == 0x0301) {  // acute
                                   priority = 0;
                                   *stop = YES;
                                   break;
                               } else if (c == 0x0300) {  // grave
                                   // Only raise if we haven't seen a better one.
                                   if (priority > 1)
                                       priority = 2;
                               }
                           }
                       }];
    return priority;
}

static NSString* cf_applyReplacements(NSString* input)
{
    // Generate a complete Latin-1/CP1252/MacRoman mojibake map dynamically.
    static NSDictionary<NSString*, NSArray<NSString*>*>* map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary<NSString*, NSMutableSet<NSString*>*>* m = [NSMutableDictionary dictionary];
        NSArray<NSNumber*>* encs = @[ @(NSWindowsCP1252StringEncoding), @(NSMacOSRomanStringEncoding) ];
        for (uint32_t cp = 0x00A0; cp <= 0x00FF; cp++) {
            unichar ch = (unichar) cp;
            NSString* orig = [NSString stringWithCharacters:&ch length:1];
            NSData* utf8 = [orig dataUsingEncoding:NSUTF8StringEncoding];
            if (utf8.length == 0)
                continue;
            // BFS up to 3 misdecode steps over the legacy encodings.
            NSMutableArray<NSString*>* frontier = [NSMutableArray arrayWithObject:orig];
            for (NSUInteger depth = 0; depth < 3; depth++) {
                NSMutableArray<NSString*>* next = [NSMutableArray array];
                for (NSString* cur in frontier) {
                    NSData* curUTF8 = [cur dataUsingEncoding:NSUTF8StringEncoding];
                    if (curUTF8.length == 0)
                        continue;
                    for (NSNumber* encNum in encs) {
                        NSStringEncoding enc = encNum.unsignedIntegerValue;
                        NSString* mis = [[NSString alloc] initWithData:curUTF8 encoding:enc];
                        if (mis && ![mis isEqualToString:orig]) {
                            if (!m[mis])
                                m[mis] = [NSMutableSet set];
                            [m[mis] addObject:orig];
                            [next addObject:mis];
                        }
                    }
                }
                frontier = next;
            }
        }
        NSMutableDictionary<NSString*, NSArray<NSString*>*>* finalized = [NSMutableDictionary dictionaryWithCapacity:m.count];
        [m enumerateKeysAndObjectsUsingBlock:^(NSString* key, NSMutableSet<NSString*>* vals, BOOL* stop) {
            finalized[key] = vals.allObjects;
        }];
        map = [finalized copy];
    });

    __block NSString* best = input;
    __block NSInteger bestScore = cf_mojibakeScore(best);

    [map enumerateKeysAndObjectsUsingBlock:^(NSString* key, NSArray<NSString*>* vals, BOOL* stop) {
        if ([best rangeOfString:key].location == NSNotFound) {
            return;
        }
        NSString* currentBest = best;
        NSInteger currentScore = bestScore;
        for (NSString* val in vals) {
            NSMutableString* candidate = [best mutableCopy];
            NSRange r = [candidate rangeOfString:key];
            while (r.location != NSNotFound) {
                [candidate replaceCharactersInRange:r withString:val];
                r = [candidate rangeOfString:key];
            }
            NSInteger score = cf_mojibakeScore(candidate);
            NSInteger candPriority = cf_accentPriority(candidate);
            NSInteger bestPriority = cf_accentPriority(currentBest);
            if (score < currentScore || (score == currentScore && candPriority < bestPriority) ||
                (score == currentScore && candPriority == bestPriority && [candidate length] < [currentBest length])) {
                currentBest = candidate;
                currentScore = score;
            }
        }
        best = currentBest;
        bestScore = currentScore;
    }];

    return cf_normalize(best);
}

static NSString* cf_simplePass(NSString* input)
{
    NSString* normalized = cf_normalize(input);
    cf_logStage(@"simplePass.normalize", normalized);
    NSString* replaced = cf_applyReplacements(normalized);
    cf_logStage(@"simplePass.replacements1", replaced);

    static NSCharacterSet* markerSet;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        markerSet = [NSCharacterSet characterSetWithCharactersInString:@"ÃÂðÐÑ"];
    });

    if ([replaced rangeOfCharacterFromSet:markerSet].location == NSNotFound) {
        return replaced;
    }

    NSMutableString* cleaned = [NSMutableString stringWithCapacity:replaced.length];
    [replaced enumerateSubstringsInRange:NSMakeRange(0, replaced.length)
                                 options:NSStringEnumerationByComposedCharacterSequences
                              usingBlock:^(NSString* substring, NSRange __, NSRange ___, BOOL* stop) {
                                  if (![markerSet characterIsMember:[substring characterAtIndex:0]]) {
                                      [cleaned appendString:substring];
                                  }
                              }];

    NSString* secondPass = cf_applyReplacements(cf_normalize(cleaned));
    cf_logStage(@"simplePass.afterStrip", secondPass);
    return secondPass;
}

static BOOL hasBadMarkers(NSString* s)
{
    if (s.length == 0) {
        return NO;
    }
    NSRange r1 = [s rangeOfString:@"Ã"];
    NSRange r2 = [s rangeOfString:@"Â"];
    NSRange r3 = [s rangeOfString:@"ð"];
    NSRange r4 = [s rangeOfString:@"Ð"];
    NSRange r5 = [s rangeOfString:@"Ñ"];
    return (r1.location != NSNotFound) || (r2.location != NSNotFound) || (r3.location != NSNotFound) || (r4.location != NSNotFound) ||
           (r5.location != NSNotFound) || (cf_replacementCount(s) > 0);
}

static BOOL cf_isLikelyClean(NSString* s)
{
    if (s == nil)
        return YES;
    if (s.length > kCFMaxStringLength)
        return NO;

    static NSCharacterSet* markerSet;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        markerSet = [NSCharacterSet characterSetWithCharactersInString:@"ÃÂðÐÑ"];
    });

    NSUInteger len = s.length;
    unichar stackBuf[256];
    unichar* buf = stackBuf;
    BOOL usedHeap = NO;
    if (len > (sizeof(stackBuf) / sizeof(unichar))) {
        buf = (unichar*) malloc(len * sizeof(unichar));
        if (!buf)
            return NO;
        usedHeap = YES;
    }
    [s getCharacters:buf range:NSMakeRange(0, len)];

    NSCharacterSet* ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    BOOL prevSpace = NO;
    BOOL bad = NO;
    for (NSUInteger i = 0; i < len && !bad; i++) {
        unichar c = buf[i];
        if ([markerSet characterIsMember:c] || c == 0xFFFD || c == 0x00A0) {
            bad = YES;
            break;
        }
        BOOL isSpace = (c == ' ');
        if (isSpace && prevSpace) {
            bad = YES;
            break;
        }
        if (i == 0 || i == len - 1) {
            if ([ws characterIsMember:c]) {
                bad = YES;
                break;
            }
        }
        prevSpace = isSpace;
    }
    if (usedHeap)
        free(buf);
    return !bad;
}

static void cf_logStage(NSString* label, NSString* value)
{
#if DEBUG_SANITIZER
    fprintf(stderr, "[Sanitized][%s] '%s' (hex: %s)\n", label.UTF8String ?: "(nil)", value.UTF8String ?: "", [cf_hexUTF8(value ?: @"") UTF8String]);
#endif
}

@implementation NSString (Sanitized)

- (NSString*)sanitizedMetadataString
{
    NSString* s = self ?: @"";
    if (cf_isLikelyClean(s)) {
        return s;
    }
    // Normalize early to reduce noise and collapse whitespace.
    s = cf_normalize(s);

    // Build candidates: base (with replacements), Latin1->UTF8, MacRoman->UTF8,
    // and legacy recodes.
    NSMutableArray<NSString*>* candidates = [NSMutableArray arrayWithObject:cf_applyReplacements(s)];

    NSString* latin1 = cf_reinterpret(s, NSISOLatin1StringEncoding, NSUTF8StringEncoding);
    if (latin1)
        [candidates addObject:cf_applyReplacements(latin1)];

    NSString* mac = cf_reinterpret(s, NSMacOSRomanStringEncoding, NSUTF8StringEncoding);
    if (mac)
        [candidates addObject:cf_applyReplacements(mac)];

    // Also consider the “UTF-8 bytes decoded as legacy” path we used before.
    for (NSNumber* encNum in @[ @(NSMacOSRomanStringEncoding), @(NSWindowsCP1252StringEncoding) ]) {
        NSData* asUTF8 = [s dataUsingEncoding:NSUTF8StringEncoding];
        if (asUTF8.length == 0)
            continue;
        NSString* legacy = [[NSString alloc] initWithData:asUTF8 encoding:encNum.unsignedIntegerValue];
        if (!legacy)
            continue;
        [candidates addObject:cf_applyReplacements(legacy)];
    }

    // Pick the candidate with the lowest mojibake score.
    NSString* best = candidates.firstObject;
    NSInteger bestScore = cf_mojibakeScore(best);
    for (NSString* cand in candidates) {
        NSInteger score = cf_mojibakeScore(cand);
        if (score < bestScore) {
            best = cand;
            bestScore = score;
        }
    }

    s = cf_applyReplacements(best);
    cf_logStage(@"pass1.afterReplacements", s);

    // Pass 2: if markers remain, strip them, then re-apply replacements and
    // normalize.
    if (hasBadMarkers(s)) {
        cf_logStage(@"markers.present", s);
        NSCharacterSet* markerSet = [NSCharacterSet characterSetWithCharactersInString:@"ÃÂðÐÑ"];
        NSMutableString* cleaned = [NSMutableString stringWithCapacity:s.length];
        [s enumerateSubstringsInRange:NSMakeRange(0, s.length)
                              options:NSStringEnumerationByComposedCharacterSequences
                           usingBlock:^(NSString* substring, NSRange __, NSRange ___, BOOL* stop) {
                               if (![markerSet characterIsMember:[substring characterAtIndex:0]]) {
                                   [cleaned appendString:substring];
                               }
                           }];
        s = cf_applyReplacements(cf_normalize(cleaned));
        cf_logStage(@"pass2.afterStrip", s);
    }

    cf_logStage(@"final.output", s);
    return s;
}

- (BOOL)isLikelyMojibakeMetadata
{
    if (self.length == 0) {
        return NO;
    }

    NSInteger score = cf_mojibakeScore(self);
    if (score == 0) {
        return NO;
    }

    NSString* sanitized = [self sanitizedMetadataString];
    if (![sanitized isEqualToString:self]) {
        return YES;
    }

    return score > 2;
}

@end
