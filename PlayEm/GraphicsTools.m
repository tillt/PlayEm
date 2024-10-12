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


@end
