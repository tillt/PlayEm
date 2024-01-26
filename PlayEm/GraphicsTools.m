//
//  GraphicsTools.m
//  PlayEm
//
//  Created by Till Toenshoff on 21.01.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import "GraphicsTools.h"

float ScaleWithOriginalFrame(float originalValue, float originalSize, float newSize)
{
    return (originalValue * newSize) / originalSize;
}

@implementation GraphicsTools

+ (MTLClearColor)MetalClearColorFromColor:(NSColor*)color
{
    NSColor *out = [color colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];

    double red = [out redComponent];
    double green = [out greenComponent];
    double blue = [out blueComponent];
    double alpha = [out alphaComponent];
    
    return MTLClearColorMake(red, green, blue, alpha);
}

+ (vector_float4)ShaderColorFromColor:(NSColor*)color
{
    NSColor *out = [color colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];

    double red = [out redComponent];
    double green = [out greenComponent];
    double blue = [out blueComponent];
    double alpha = [out alphaComponent];
    
    vector_float4 color_vec = {red, green, blue, alpha};
    
    return color_vec;
}

@end
