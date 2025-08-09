//
//  NSImage+Average.m
//  PlayEm
//
//  Created by Till Toenshoff on 3/30/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import "NSImage+Average.h"

@implementation NSImage (Average)

- (NSColor*)averageColor
{
    unsigned char rgba[4];

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(rgba, 1, 1, 8, 4, colorSpace, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);

    NSRect imageRect = NSMakeRect(0, 0, self.size.width, self.size.height);

    CGImageRef cgImage = [self CGImageForProposedRect:&imageRect context:NULL hints:nil];

    CGContextDrawImage(context, CGRectMake(0, 0, 1, 1), cgImage);

    CGColorSpaceRelease(colorSpace);
    CGContextRelease(context);

    if(rgba[3] > 0) {
        const CGFloat alpha = ((CGFloat)rgba[3])/255.0;
        const CGFloat multiplier = alpha / 255.0;
        return [NSColor colorWithRed:((CGFloat)rgba[0]) * multiplier
                               green:((CGFloat)rgba[1]) * multiplier
                                blue:((CGFloat)rgba[2]) * multiplier
                               alpha:alpha];
    }
    else {
        return [NSColor colorWithRed:((CGFloat)rgba[0])/255.0
                               green:((CGFloat)rgba[1])/255.0
                                blue:((CGFloat)rgba[2])/255.0
                               alpha:((CGFloat)rgba[3])/255.0];
    }
}

@end
