//
//  NSImage+Resize.m
//  PlayEm
//
//  Created by Till Toenshoff on 3/29/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import "NSImage+Resize.h"

@implementation NSImage (Resize)

+ (NSImage*)resizedImage:(NSImage*)image size:(NSSize)size
{
    NSImage* sourceImage = image;
    
    if (![image isValid]){
        NSLog(@"invalid image");
        return nil;
    }

    NSImage* smallImage = [[NSImage alloc] initWithSize:size];

    [smallImage lockFocus];

    [sourceImage setSize:size];
    
    NSGraphicsContext* context = [NSGraphicsContext currentContext];
    [context setImageInterpolation:NSImageInterpolationHigh];
    [context setShouldAntialias:YES];
    context.colorRenderingIntent = NSColorRenderingIntentPerceptual;
    
    [sourceImage drawAtPoint:NSZeroPoint
                    fromRect:CGRectMake(0, 0, size.width, size.height)
                   operation:NSCompositingOperationCopy
                    fraction:1.0];

    [smallImage unlockFocus];

    return smallImage;
}

@end
