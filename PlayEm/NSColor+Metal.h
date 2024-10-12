//
//  NSColor+Metal.m
//  PlayEm
//
//  Created by Till Toenshoff on 12.10.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <MetalKit/MetalKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSColor (Metal)

+ (MTLClearColor)MetalClearColorFromColor:(NSColor*)color;
+ (vector_float4)ShaderColorFromColor:(NSColor*)color;

@end

NS_ASSUME_NONNULL_END
