//
//  TiledScrollView.h
//  PlayEm
//
//  Created by Till Toenshoff on 05.12.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

NS_ASSUME_NONNULL_BEGIN

extern const CGFloat kDirectWaveViewTileWidth;

@class VisualSample;

@interface TiledScrollView : NSScrollView

@property (strong, nonatomic) CALayer* rastaLayer;

@property (strong, nonatomic) CAShapeLayer* aheadVibranceFxLayerMask;
@property (strong, nonatomic) CALayer* aheadVibranceFxLayer;
@property (strong, nonatomic) CALayer* trailBloomFxLayer;

//@property (nonatomic, strong) IBOutlet NSNumber* tileWidth;
- (void)updatedHeadPosition;

@end 


@interface WaveView : NSView

@property (assign, nonatomic) CGSize headImageSize;
@property (strong, nonatomic) CALayer* headLayer;
@property (strong, nonatomic) CALayer* hudLayer;
//@property (assign, nonatomic) NSTimeInterval duration;
@property (assign, nonatomic) unsigned long long frames;
@property (assign, nonatomic) unsigned long long currentFrame;
@property (strong, nonatomic) NSColor* color;
@property (strong, nonatomic) CIFilter* headFx;
@property (strong, nonatomic) CALayer* headBloomFxLayer;
@property (assign, nonatomic) CGFloat head;

//@property (strong, nonatomic) CALayer* trailBloomFxLayer;
//@property (strong, nonatomic) CALayer* aheadVibranceFxLayer;

@property (weak, nonatomic) IBOutlet id<CALayerDelegate> layerDelegate;

//- (void)updateDuration:(NSTimeInterval)duration;
//- (void)updateCurrentTime:(NSTimeInterval)seconds;
- (void)userInitiatedScrolling;
- (void)userEndsScrolling;

@end

NS_ASSUME_NONNULL_END
