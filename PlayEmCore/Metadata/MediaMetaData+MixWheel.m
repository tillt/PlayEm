//
//  MediaMetaData+MixWheel.m
//  PlayEm
//
//  Created by Till Toenshoff on 1/14/26.
//  Copyright © 2026 Till Toenshoff. All rights reserved.
//
#import "MediaMetaData.h"

@implementation MediaMetaData (MixWheel)

+ (NSString* _Nullable)correctedKeyNotation:(NSString* _Nullable)key
{
    // We are trying to catch all synonymous scales here additionally
    // to the 24 sectors of the MixWheel.
    NSDictionary* mixWheel = @{
        @"Abmin" : @"1A",  // G♯ minor/A♭ minor
        @"G#min" : @"1A",  // G♯ minor/A♭ minor
        @"Cbmaj" : @"1B",  // B major/C♭ major
        @"Bmaj" : @"1B",   // B major/C♭ major
        @"Ebmin" : @"2A",  // D♯ minor/E♭ minor
        @"D#min" : @"2A",  // D♯ minor/E♭ minor
        @"F#maj" : @"2B",  // F♯ major/G♭ major
        @"Gbmaj" : @"2B",  // F♯ major/G♭ major
        @"A#min" : @"3A",  // A♯ minor/B♭ minor
        @"Bbmin" : @"3A",  // A♯ minor/B♭ minor
        @"C#maj" : @"3B",  // C♯ major/D♭ major
        @"Dbmaj" : @"3B",  // C♯ major/D♭ major
        @"Fmin" : @"4A",
        @"Abmaj" : @"4B",  // G♯ major/A♭ major
        @"G#maj" : @"4B",  // G♯ major/A♭ major
        @"Cmin" : @"5A",
        @"Ebmaj" : @"5B",  // D♯ major/E♭ major
        @"D#maj" : @"5B",  // D♯ major/E♭ major
        @"Gmin" : @"6A",
        @"A#maj" : @"6B",  // A♯ major/B♭ major
        @"Bbmaj" : @"6B",  // A♯ major/B♭ major
        @"Dmin" : @"7A",
        @"Fmaj" : @"7B",
        @"Amin" : @"8A",
        @"Cmaj" : @"8B",
        @"Emin" : @"9A",
        @"Gmaj" : @"9B",
        @"Cbmin" : @"10A",  // B minor/C♭ minor
        @"Bmin" : @"10A",   // B minor/C♭ minor
        @"Dmaj" : @"10B",
        @"Gbmin" : @"11A",  // F♯ minor/G♭ minor
        @"F#min" : @"11A",  // F♯ minor/G♭ minor
        @"Amaj" : @"11B",
        @"C#min" : @"12A",  // C♯ minor/D♭ minor
        @"Dbmin" : @"12A",
        @"Emaj" : @"12B",
    };

    if (key == nil || key.length == 0) {
        return key;
    }

    // Shortcut when the given key is a proper one already.
    NSArray* properValues = [mixWheel allValues];
    if ([properValues indexOfObject:key] != NSNotFound) {
        return key;
    }

    // Easy cases map already, shortcut those.
    NSString* mappedKey = [mixWheel objectForKey:key];
    if (mappedKey != nil) {
        return mappedKey;
    }

    if (key.length > 1) {
        // Lets patch minor defects in place so we can map later...
        // Get a possible note specifier.
        NSString* s = [key substringWithRange:NSMakeRange(1, 1)];
        if ([s isEqualToString:@"o"] || [s isEqualToString:@"♯"]) {
            key = [NSString stringWithFormat:@"%@#%@", [key substringToIndex:1], [key substringFromIndex:2]];
        } else if ([s isEqualToString:@"♭"]) {
            key = [NSString stringWithFormat:@"%@b%@", [key substringToIndex:1], [key substringFromIndex:2]];
        }
        // Easy cases map now, shortcut those.
        NSString* mappedKey = [mixWheel objectForKey:key];
        if (mappedKey != nil) {
            return mappedKey;
        }
    }

    NSString* patchedKey = nil;
    unichar p = [key characterAtIndex:0];
    unichar t = [key characterAtIndex:key.length - 1];

    if ((p >= '1' && p <= '9')) {
        if (t == 'm' || t == 'n') {
            patchedKey = [NSString stringWithFormat:@"%@A", [key substringToIndex:key.length - 1]];
        } else {
            patchedKey = [NSString stringWithFormat:@"%@B", key];
        }
        return patchedKey;
    }

    if (t == 'm') {
        patchedKey = [NSString stringWithFormat:@"%@in", key];
    } else if (t != 'n') {
        patchedKey = [NSString stringWithFormat:@"%@maj", key];
    } else {
        patchedKey = key;
    }

    mappedKey = [mixWheel objectForKey:patchedKey];
    if (mappedKey != nil) {
        return mappedKey;
    }

    NSLog(@"couldnt map key %@ (%@)", key, patchedKey);

    return key;
}

@end
