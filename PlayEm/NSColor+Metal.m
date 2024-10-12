//
//  NSColor+ColorMetal.h
//  PlayEm
//
//  Created by Till Toenshoff on 12.10.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "NSColor+Metal.h"

NS_ASSUME_NONNULL_BEGIN

@implementation NSColor (Metal)

+ (MTLClearColor)MetalClearColorFromColor:(NSColor*)color
{
    NSColor *out = [color colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];

    double red = [out redComponent];
    double green = [out greenComponent];
    double blue = [out blueComponent];
    double alpha = [out alphaComponent];
    
    return MTLClearColorMake(red, green, blue, alpha);
}

+ (vector_float4)ShaderColorFromColor:(NSColor*)color
{
    NSColor *out = [color colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];

    double red = [out redComponent];
    double green = [out greenComponent];
    double blue = [out blueComponent];
    double alpha = [out alphaComponent];
    
    vector_float4 color_vec = {red, green, blue, alpha};
    
    return color_vec;
}

@end

NS_ASSUME_NONNULL_END
