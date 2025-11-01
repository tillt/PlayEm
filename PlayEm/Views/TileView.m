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
#import "BeatLayerDelegate.h"
#import "WaveLayerDelegate.h"


@implementation TileView

- (nonnull instancetype)initWithFrame:(CGRect)frameRect layerDelegate:(id<WaveLayerDelegate>)layerDelegate overlayLayerDelegate:(id<BeatLayerDelegate>)overlayLayerDelegate
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.canDrawConcurrently = YES;
        self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;
        self.layer = [self makeBackingLayer];
        self.layer.frame = frameRect;
        self.layer.name = @"TileViewBackingLayer";
        
        _overlayLayer = [self makeOverlayLayer];
        _overlayLayer.frame = CGRectMake(0.0,
                                         0.0,
                                         frameRect.size.width,
                                         frameRect.size.height);
        _overlayLayer.name = @"TileViewOverlayLayer";
        [self.layer addSublayer:_overlayLayer];
        
        self.layer.delegate = layerDelegate;
        _overlayLayer.delegate = overlayLayerDelegate;
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

- (void)viewDidMoveToSuperview
{
    [super viewDidMoveToSuperview];
    [self.layer setNeedsDisplay];
    [self.overlayLayer setNeedsDisplay];
}

@end
