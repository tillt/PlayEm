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
@class NSGraphicsContext;
@class NSView;
@class MTKView;
@class NSColor;
@class AudioController;
@class VisualSample;

@interface Visualizer : NSObject

@property (strong, nonatomic) NSColor *lightColor;
@property (strong, nonatomic) NSColor *darkColor;
@property (strong, nonatomic) NSColor *backgroundColor;

+ (NSImage *)imageFromVisualSample:(VisualSample *)sample start:(NSTimeInterval)start duration:(NSTimeInterval)duration size:(CGSize)size;
+ (NSImage *)imageFromSample:(Sample *)sample start:(NSTimeInterval)start duration:(NSTimeInterval)duration size:(CGSize)size;

+ (void)drawVisualSample:(VisualSample *)visual start:(NSTimeInterval)start duration:(NSTimeInterval)duration size:(CGSize)size color:(CGColorRef)color context:(CGContextRef)context;

+ (void)drawVisualSample:(VisualSample *)visual start:(unsigned long int )start length:(unsigned long int )length size:(CGSize)size color:(CGColorRef)color context:(CGContextRef)context;

//- (void)process:(AVAudioPCMBuffer *)audioPCMBuffer offet:(size_t)offset bufferSamples:(size_t) bufferSamples channels:(int)channels;

- (void)play:(AudioController *)audio visual:(VisualSample *)visual;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
