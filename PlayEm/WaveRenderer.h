//
//  WaveRenderer.h
//  PlayEm
//
//  Created by Till Toenshoff on 21.01.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import <MetalKit/MetalKit.h>

NS_ASSUME_NONNULL_BEGIN

@class AudioController;
@class VisualSample;
@class NSColor;

@protocol WaveRendererDelegate <NSObject>

- (VisualSample*)visualSample;
- (AudioController*)audioController;

@end

@interface WaveRenderer : NSObject <MTKViewDelegate>

- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)view color:(NSColor *)color background:(NSColor *)background delegate:(id<WaveRendererDelegate>)delegate;

@end

NS_ASSUME_NONNULL_END
