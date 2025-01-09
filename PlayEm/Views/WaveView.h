//
//  WaveView.h
//  PlayEm
//
//  Created by Till Toenshoff on 16.08.23.
//  Copyright © 2023 Till Toenshoff. All rights reserved.
//

#ifndef WaveView_h
#define WaveView_h

#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

@protocol WaveViewHeadDelegate <NSObject>
- (void)updatedHeadPosition;
@end

/// WaveView is the document view of the entire sample file.
@interface WaveView : NSView

@property (assign, nonatomic) CGSize headImageSize;
@property (strong, nonatomic) CALayer* headLayer;
@property (assign, nonatomic) unsigned long long frames;
@property (assign, nonatomic) unsigned long long currentFrame;
@property (assign, nonatomic) CGFloat head;
@property (strong, nonatomic) NSColor* color;
@property (strong, nonatomic) CIFilter* headFx;
@property (strong, nonatomic) CALayer* headBloomFxLayer;

@property (weak, nonatomic) id<CALayerDelegate> waveLayerDelegate;
@property (weak, nonatomic) id<CALayerDelegate> beatLayerDelegate;
@property (weak, nonatomic) id<WaveViewHeadDelegate> headDelegate;

//- (void)updateDuration:(NSTimeInterval)duration;
//- (void)updateCurrentTime:(NSTimeInterval)seconds;
- (void)userInitiatedScrolling;
- (void)userEndsScrolling;
- (void)updateHeadPositionTransaction;
- (void)invalidateTiles;

@end

#endif /* WaveView_h */
