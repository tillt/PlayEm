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

@implementation BeatLayerDelegate
{
}

#pragma mark Layer delegate

- (void)drawLayer:(CALayer*)layer inContext:(CGContextRef)context
{
    if (_waveView == nil || _beatSample == nil || layer.frame.origin.x < 0) {
        return;
    }
    const double framesPerPixel = _beatSample.framesPerPixel;

    CGContextSetAllowsAntialiasing(context, YES);
    CGContextSetShouldAntialias(context, YES);

    CGFloat start = layer.superlayer.frame.origin.x > 0 ? layer.superlayer.frame.origin.x : 0.0f;

    NSData* buffer = [_beatSample beatsFromOrigin:start];
    if (buffer == nil) {
        NSLog(@"beat buffer from screen position %f not yet available", start);
        return;
    }
    
    BeatEvent* events = (BeatEvent*)buffer.bytes;
    const float maxBeatCount = buffer.length / sizeof(BeatEvent);
    
    CGColorRef barColor = [[[Defaults sharedDefaults] barColor] CGColor];
    CGColorRef beatColor = [[[Defaults sharedDefaults] beatColor] CGColor];

    CGContextSetLineWidth(context, 3.0);
    
    for (unsigned int beatIndex = 0; beatIndex < maxBeatCount; beatIndex++) {
        const CGFloat x = floor((events[beatIndex].frame / framesPerPixel) - start);
        assert(x <= 256.0);

        CGColorRef color = (events[beatIndex].style & BeatEventStyleBar) == BeatEventStyleBar ?
                            barColor : beatColor;

        CGContextMoveToPoint(context,
                             x,
                             0.0f);
        CGContextSetStrokeColorWithColor(context, color);
        CGContextAddLineToPoint(context, x, layer.frame.size.height);
        CGContextStrokePath(context);
    }
}

@end
