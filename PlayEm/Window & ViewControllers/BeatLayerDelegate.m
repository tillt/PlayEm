//
//  BeatLayerDelegate.m
//  PlayEm
//
//  Created by Till Toenshoff on 13.08.23.
//  Copyright © 2023 Till Toenshoff. All rights reserved.
//

#import "BeatLayerDelegate.h"
#import "BeatTrackedSample.h"
#import "TotalWaveView.h"
#import "TiledScrollView.h"
#import "WaveView.h"
#import "Defaults.h"
#import "../Sample/LazySample.h"

@interface BeatLayerDelegate()

@end

@implementation BeatLayerDelegate
{
}

#pragma mark Layer delegate

- (void)setBeatSample:(BeatTrackedSample *)beatSample
{
    if (beatSample == _beatSample) {
        return;
    }
    _beatSample = beatSample;
    assert(self.waveView.frame.size.width > 0);
}

- (void)drawLayer:(CALayer*)layer inContext:(CGContextRef)context
{
    if (_waveView == nil || _beatSample == nil || layer.frame.origin.x < 0) {
        return;
    }

    CGContextSetAllowsAntialiasing(context, YES);
    CGContextSetShouldAntialias(context, YES);

    double framesPerPixel = _beatSample.sample.frames / _waveView.frame.size.width;

    CGFloat start = layer.superlayer.frame.origin.x > 0 ? layer.superlayer.frame.origin.x : 0.0f;
    const CGFloat end = start + layer.frame.size.width;

    const unsigned long long frameOffset = floor(start * framesPerPixel);
    unsigned long long currentBeatIndex = [_beatSample firstBeatIndexAfterFrame:frameOffset];
    if (currentBeatIndex == ULONG_LONG_MAX) {
        NSLog(@"beat buffer from frame %lld (screen %f) not yet available", frameOffset, start);
        return;
    }

    const unsigned long long beatCount = [_beatSample beatCount];
    assert(beatCount > 0 && beatCount != ULONG_LONG_MAX);

    while (currentBeatIndex < beatCount) {
        BeatEvent currentEvent;
        [_beatSample getBeat:&currentEvent at:currentBeatIndex++];
        
        const CGFloat x = floor((currentEvent.frame / framesPerPixel) - start);
        if (x > end - start) {
            break;
        }
        
        if ((currentEvent.style & _beatMask) == 0) {
            continue;
        }
        
        CGColorRef barColor = [[[Defaults sharedDefaults] barColor] CGColor];
        CGColorRef beatColor = [[[Defaults sharedDefaults] beatColor] CGColor];

        CGContextSetLineWidth(context, 3.0);

        CGColorRef color = (currentEvent.style & BeatEventStyleBar) == BeatEventStyleBar ?
                            barColor : beatColor;

        CGContextMoveToPoint(context, x, 0.0f);
        CGContextSetStrokeColorWithColor(context, color);
        CGContextAddLineToPoint(context, x, layer.frame.size.height);
        CGContextStrokePath(context);
    };
}

@end
