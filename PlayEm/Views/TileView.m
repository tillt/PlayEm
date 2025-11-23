//
//  TileView.m
//  PlayEm
//
//  Created by Till Toenshoff on 8/23/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import "TileView.h"
#import "../Defaults.h"
#import "WaveViewController.h"

@implementation TileView

- (nonnull instancetype)initWithFrame:(CGRect)frameRect
                        waveLayerDelegate:(id<CALayerDelegate>)waveLayerDelegate
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.canDrawConcurrently = YES;
        self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;
        self.layer = [self makeBackingLayer];
        self.layer.frame = frameRect;
        self.layer.name = @"TileViewBackingLayer";
        self.layerUsesCoreImageFilters = YES;

        _waveLayer = [self makeWaveLayer];
        _waveLayer.frame = CGRectMake(0.0, 0.0, frameRect.size.width, frameRect.size.height);
        _waveLayer.name = @"TileViewWaveLayer";
        _waveLayer.zPosition = 0.0;
        [self.layer addSublayer:_waveLayer];

        _beatLayer = [self makeOverlayLayer];
        _beatLayer.frame = CGRectMake(0.0, 0.0, frameRect.size.width, frameRect.size.height);
        _beatLayer.name = @"TileViewOverlayLayer";
        _beatLayer.zPosition = -1.0;
        [self.layer addSublayer:_beatLayer];

        _markLayer = [self makeMarkLayer];
        _markLayer.frame = CGRectMake(0.0, 0.0, frameRect.size.width, frameRect.size.height);
        _markLayer.name = @"TileViewMarkLayer";
        _markLayer.zPosition = 2.0;
        [self.layer addSublayer:_markLayer];

        _waveLayer.delegate = waveLayerDelegate;
    }
    return self;
}

- (BOOL)wantsLayer
{
    return YES;
}

- (BOOL)wantsUpdateLayer
{
    return NO;
}

- (CALayer*)makeMarkLayer
{
    CALayer* layer = [CALayer layer];
    layer.drawsAsynchronously = YES;
    layer.masksToBounds = NO;
    layer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    return layer;
}

- (CALayer*)makeOverlayLayer
{
    CALayer* layer = [CALayer layer];
    layer.drawsAsynchronously = YES;
    layer.masksToBounds = NO;
    layer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    return layer;
}

- (CALayer*)makeBackingLayer
{
    CALayer* layer = [CALayer layer];
    layer.drawsAsynchronously = YES;
    layer.masksToBounds = NO;
    layer.autoresizingMask = kCALayerNotSizable;
    return layer;
}

- (CALayer*)makeWaveLayer
{
    CALayer* layer = [CALayer layer];
    layer.drawsAsynchronously = YES;
    layer.masksToBounds = NO;
    layer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    return layer;
}

@end
