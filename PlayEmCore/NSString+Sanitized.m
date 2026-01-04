//
//  NSString+Sanitized.m
//  PlayEm
//
//  Created by Till Toenshoff on 12/27/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import "NSString+Sanitized.h"

// Bounding extremely long or corrupt strings keeps the sanitizer from doing
// heavy work (or appearing to hang) on pathological mojibake payloads.
static const NSUInteger kCFMaxScanCharacters = 4096;
static const NSUInteger kCFMaxStringLength   = 4096;

static NSInteger cf_replacementCount(NSString* s)
{
    __block NSInteger count = 0;
    NSUInteger len = MIN(s.length, kCFMaxScanCharacters);
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
    NSUInteger len = MIN(s.length, kCFMaxScanCharacters);
    [s enumerateSubstringsInRange:NSMakeRange(0, len)
                          options:NSStringEnumerationByComposedCharacterSequences
                       usingBlock:^(NSString* substring, NSRange __, NSRange ___, BOOL* stop) {
        if ([markers characterIsMember:[substring characterAtIndex:0]]) {
            bad++;
        }
    }];
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
    [m replaceOccurrencesOfString:@"\u00A0"
                        withString:@" "
                           options:0
                             range:NSMakeRange(0, m.length)];

    static NSRegularExpression* wsRE;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        wsRE = [NSRegularExpression regularExpressionWithPattern:@"\\s+"
                                                         options:0
                                                           error:nil];
    });
    NSString* collapsed = [wsRE stringByReplacingMatchesInString:m
                                                         options:0
                                                           range:NSMakeRange(0, m.length)
                                                    withTemplate:@" "];
    return [collapsed stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
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
    return (r1.location != NSNotFound) ||
           (r2.location != NSNotFound) ||
           (r3.location != NSNotFound) ||
           (r4.location != NSNotFound) ||
           (r5.location != NSNotFound) ||
           (cf_replacementCount(s) > 0);
}

@implementation NSString (Sanitized)

- (NSString*)sanitizedMetadataString
{
    NSString* original = self ?: @"";
    NSString* best = cf_normalize(original);
    // If the string looks clean, keep it as-is; avoids over-aggressive rewrites of
    // legitimate characters (em dashes, Cyrillic, etc.).
    if (!hasBadMarkers(best)) {
        return best;
    }

    NSInteger bestScore = cf_mojibakeScore(best);
    NSData *originalUTF8 = [original dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:NO];

    // Iterative Latin1 -> UTF8 pass (bounded).
    NSString* current = best;
    for (int i = 0; i < 3; i++) {
        NSData* latin = [current dataUsingEncoding:NSISOLatin1StringEncoding allowLossyConversion:NO];
        if (latin == nil) {
            break;
        }
        NSString* decoded = [[NSString alloc] initWithData:latin encoding:NSUTF8StringEncoding];
        if (decoded == nil || [decoded isEqualToString:current]) {
            break;
        }
        decoded = cf_normalize(decoded);
        NSInteger score = cf_mojibakeScore(decoded);
        if (score < bestScore || (score == bestScore && ![decoded isEqualToString:best])) {
            best = decoded;
            bestScore = score;
            current = decoded;
        } else {
            break;  // stop if it gets worse
        }
    }

    // UTF-16 fallback attempts if markers persist.
    if (originalUTF8.length > 0 && hasBadMarkers(best)) {
        NSArray<NSNumber *> *encs = @[@(NSUTF16LittleEndianStringEncoding), @(NSUTF16BigEndianStringEncoding)];
        for (NSNumber *encNum in encs) {
            NSStringEncoding enc = encNum.unsignedIntegerValue;
            NSString *decoded = [[NSString alloc] initWithData:originalUTF8 encoding:enc];
            if (decoded.length > 0) {
                decoded = cf_normalize(decoded);
                NSInteger score = cf_mojibakeScore(decoded);
                if (score < bestScore) {
                    best = decoded;
                    bestScore = score;
                }
            }
        }
    }

    // Single CP1252 attempt.
    NSData* cpBytes = [best dataUsingEncoding:NSWindowsCP1252StringEncoding allowLossyConversion:NO];
    if (cpBytes != nil) {
        NSString* cpDecoded = [[NSString alloc] initWithData:cpBytes encoding:NSUTF8StringEncoding];
        if (cpDecoded.length > 0) {
            cpDecoded = cf_normalize(cpDecoded);
            NSInteger score = cf_mojibakeScore(cpDecoded);
            if (score < bestScore) {
                best = cpDecoded;
                bestScore = score;
            }
        }
    }

    // Targeted replacements for stubborn mojibake sequences seen in Shazam payloads.
    static NSDictionary<NSString*, NSString*>* replacements;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        replacements = @{
            // "é" and friends mangled into multi-byte garbage.
            @"\u221a\u00ae": @"é",
            @"Ã©": @"é",
            @"Ã¨": @"è",
            @"Ã¡": @"á",
            @"Ã¢": @"â",
            @"Ãº": @"ú",
            @"Ã³": @"ó",
            @"Ã¶": @"ö",
            @"Ã¼": @"ü",
        };
    });
    // Byte-pattern replacement for E2 88 9A AE (common mojibake sequence we see).
    NSData* bytes = [best dataUsingEncoding:NSISOLatin1StringEncoding allowLossyConversion:YES];
    if (bytes) {
        static const uint8_t badSeq[] = {0xE2, 0x88, 0x9A, 0xAE};
        const uint8_t goodSeq[] = {0xC3, 0xA9};  // UTF-8 for 'é'
        NSMutableData* patched = [NSMutableData data];
        const uint8_t* p = bytes.bytes;
        NSUInteger len = bytes.length;
        BOOL didReplace = NO;
        for (NSUInteger i = 0; i < len;) {
            if (i + 4 <= len &&
                p[i] == badSeq[0] && p[i + 1] == badSeq[1] &&
                p[i + 2] == badSeq[2] && p[i + 3] == badSeq[3]) {
                [patched appendBytes:goodSeq length:sizeof(goodSeq)];
                i += 4;
                didReplace = YES;
            } else {
                [patched appendBytes:&p[i] length:1];
                i += 1;
            }
        }
        NSString* recovered = [[NSString alloc] initWithData:patched encoding:NSUTF8StringEncoding];
        if (recovered.length > 0) {
            recovered = cf_normalize(recovered);
            best = recovered;
            bestScore = cf_mojibakeScore(recovered);
#ifdef DEBUG
            if (didReplace) {
                NSLog(@"replaced E2 88 9A AE -> C3 A9");
            }
#endif
        }
    }

    NSMutableString* fixed = [best mutableCopy];
    [replacements enumerateKeysAndObjectsUsingBlock:^(NSString* key, NSString* val, BOOL* stop) {
        NSRange r = [fixed rangeOfString:key];
        while (r.location != NSNotFound) {
            [fixed replaceCharactersInRange:r withString:val];
            r = [fixed rangeOfString:key];
        }
    }];

    NSString* normalizedFixed = cf_normalize(fixed);
    fixed = [normalizedFixed mutableCopy];
    NSInteger repScore = cf_mojibakeScore(fixed);
    if (repScore < bestScore || (repScore == bestScore && ![fixed isEqualToString:best])) {
        best = fixed;
        bestScore = repScore;
    }

    return best;
}

@end
