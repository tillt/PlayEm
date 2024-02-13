//
//  MetalWaveView.h
//  PlayEm
//
//  Created by Till Toenshoff on 26.01.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import <MetalKit/MetalKit.h>

@class WaveRenderer;

NS_ASSUME_NONNULL_BEGIN

@interface MetalWaveView : MTKView

@property (nonatomic, assign) CGRect documentVisibleRect;
@property (nonatomic, assign) CGRect documentTotalRect;
@property (nonatomic, assign) CGRect rect;


@property (nonatomic, strong) WaveRenderer* waveRenderer;
@property (assign, nonatomic) unsigned long long frames;
@property (assign, nonatomic) unsigned long long currentFrame;

@end

NS_ASSUME_NONNULL_END
