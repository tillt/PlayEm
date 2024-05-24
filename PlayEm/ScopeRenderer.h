//
//  ScopeRenderer.h
//  PlayEm
//
//  Created by Till Toenshoff on 10.05.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import <MetalKit/MetalKit.h>

NS_ASSUME_NONNULL_BEGIN

@class AudioController;
@class VisualSample;
@class NSColor;

@protocol ScopeRendererDelegate <NSObject>
- (VisualSample*)visualSample;
- (AudioController*)audioController;
@end

@interface ScopeRenderer : NSObject <MTKViewDelegate>

@property (weak, nonatomic) NSLevelIndicator* level;
@property (assign, nonatomic) unsigned long long frames;
@property (assign, nonatomic) unsigned long long currentFrame;

- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)view color:(NSColor *)color fftColor:(NSColor *)fftColor background:(NSColor *)background delegate:(id<ScopeRendererDelegate>)delegate;
- (void)loadMetalWithView:(nonnull MTKView*)view;
- (void)play:(nonnull AudioController *)audio visual:(nonnull VisualSample *)visual scope:(nonnull MTKView *)scope;
- (void)stop:(MTKView *)scope;

@end

NS_ASSUME_NONNULL_END
