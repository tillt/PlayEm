//
//  TiledScrollView.h
//  PlayEm
//
//  Created by Till Toenshoff on 05.12.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import "WaveView.h"

NS_ASSUME_NONNULL_BEGIN

extern const CGFloat kDirectWaveViewTileWidth;

@class VisualSample;

@interface TiledScrollView : NSScrollView<WaveViewHeadDelegate>

@property (strong, nonatomic) CALayer* rastaLayer;

@property (strong, nonatomic) CAShapeLayer* aheadVibranceFxLayerMask;
@property (strong, nonatomic) CALayer* aheadVibranceFxLayer;
@property (strong, nonatomic) CALayer* trailBloomFxLayer;

@end


NS_ASSUME_NONNULL_END
