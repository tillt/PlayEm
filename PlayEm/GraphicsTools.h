//
//  GraphicsTools.h
//  PlayEm
//
//  Created by Till Toenshoff on 21.01.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <MetalKit/MetalKit.h>

NS_ASSUME_NONNULL_BEGIN

float ScaleWithOriginalFrame(float originalValue, float originalSize, float newSize);

@interface GraphicsTools : NSObject

+ (MTLClearColor)MetalClearColorFromColor:(NSColor*)color;
+ (vector_float4)ShaderColorFromColor:(NSColor*)color;

@end

NS_ASSUME_NONNULL_END
