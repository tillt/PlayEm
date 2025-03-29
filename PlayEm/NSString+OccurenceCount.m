//
//  NSString+OccurenceCount.m
//  PlayEm
//
//  Created by Till Toenshoff on 3/21/25.
//  From https://stackoverflow.com/a/15947190/91282
//   and https://stackoverflow.com/a/5310084/91282
//

#import "NSString+OccurenceCount.h"

@implementation NSString (OccurrenceCount)

- (NSUInteger)occurrenceCountOfCharacter:(UniChar)character
{
    CFStringRef selfAsCFStr = (__bridge CFStringRef)self;

    CFStringInlineBuffer inlineBuffer;

    CFIndex length = CFStringGetLength(selfAsCFStr);
    CFStringInitInlineBuffer(selfAsCFStr, &inlineBuffer, CFRangeMake(0, length));

    NSUInteger counter = 0;

    for (CFIndex i = 0; i < length; i++) {
        UniChar c = CFStringGetCharacterFromInlineBuffer(&inlineBuffer, i);
        if (c == character) {
            counter++;
        }
    }

    return counter;
}

- (NSUInteger)occurrenceCountOfString:(NSString*)string
{
    NSUInteger strCount = [self length] - [[self stringByReplacingOccurrencesOfString:string withString:@""] length];
    return strCount / [string length];
}

@end
