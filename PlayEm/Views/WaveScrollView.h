//
//  WaveScrollView.h
//  PlayEm
//
//  Created by Till Toenshoff on 8/23/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import "TiledScrollView.h"

NS_ASSUME_NONNULL_BEGIN

@interface WaveScrollView : TiledScrollView<WaveViewHeadDelegate>

@property (strong, nonatomic) CALayer* rastaLayer;

@property (strong, nonatomic) CAShapeLayer* aheadVibranceFxLayerMask;
@property (strong, nonatomic) CALayer* aheadVibranceFxLayer;
@property (strong, nonatomic) CALayer* trailBloomFxLayer;

@end

NS_ASSUME_NONNULL_END
