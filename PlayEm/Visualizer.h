//
//  Visualizer.h
//  PlayEm
//
//  Created by Till Toenshoff on 11.04.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class Sample;
@class VisualSample;
@class AVAudioPCMBuffer;
@class NSView;

@interface Visualizer : NSObject

- (id)initWithFFTView:(NSView *)fftView scopeView:(NSView *)scopeView;

- (void)resizeScope:(NSSize)size;
- (void)resizeFFT:(NSSize)size;

+ (NSImage *)imageFromVisualSample:(VisualSample *)sample start:(NSTimeInterval)start duration:(NSTimeInterval)duration size:(CGSize)size;
+ (NSImage *)imageFromSample:(Sample *)sample start:(NSTimeInterval)start duration:(NSTimeInterval)duration size:(CGSize)size;

- (void)process:(AVAudioPCMBuffer *)audioPCMBuffer offet:(size_t)offset bufferSamples:(size_t) bufferSamples channels:(int)channels;

@end

NS_ASSUME_NONNULL_END
