//
//  MetalWaveView.m
//  PlayEm
//
//  Created by Till Toenshoff on 26.01.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import "MetalWaveView.h"
#import "WaveRenderer.h"

@implementation MetalWaveView
{
}

- (void)awakeFromNib
{
    [super awakeFromNib];
    //self.paused = YES;
    self.enableSetNeedsDisplay = NO;
    self.layer.opaque = NO;
    self.layer.backgroundColor = [[NSColor colorWithRed:0 green:0 blue:0 alpha:0] CGColor];
    self.clearColor = MTLClearColorMake(0, 0, 0, 0);
}

- (void)viewDidMoveToSuperview
{
    [super viewDidMoveToSuperview];
    _rect = self.bounds;
}

- (void)invalidateTiles
{
    [_waveRenderer invalidateTiles];
}

- (void)setFrames:(unsigned long long)frames
{
    if (_waveRenderer.frames == frames) {
        return;
    }
    _waveRenderer.frames = frames;
    [self invalidateTiles];
    self.currentFrame = 0;
}

- (void)setCurrentFrame:(unsigned long long)frame
{
    if (_waveRenderer.currentFrame == frame) {
        return;
    }
    if (_waveRenderer.frames == 0.0) {
        return;
    }
    _waveRenderer.currentFrame = frame;
    
    [self updateScrollingState];

    [self draw];
}

- (void)updateScrollingState
{
    CGFloat head = (self.documentTotalRect.size.width * _waveRenderer.currentFrame) / _waveRenderer.frames;
    self.documentVisibleRect = CGRectMake(MAX(floor(head - (_rect.size.width / 2.0)), 0.0),
                                         0.0,
                                          _rect.size.width,
                                          _rect.size.height);
}

@end
