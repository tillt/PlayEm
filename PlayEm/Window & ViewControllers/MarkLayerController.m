//
//  MarkLayerController.m
//  PlayEm
//
//  Created by Till Toenshoff on 11/9/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import "MarkLayerController.h"
#import "TrackList.h"
#import "TotalWaveView.h"
#import "TiledScrollView.h"
#import "WaveView.h"
#import "Defaults.h"
#import "../Sample/LazySample.h"
#import "TrackList.h"
#import "IdentifiedTrack.h"
#import "TileView.h"
#import "../Sample/BeatTrackedSample.h"
#import "../Sample/VisualSample.h"
#import "../Sample/VisualPair.h"

@interface MarkLayerController()

@end

@implementation MarkLayerController
{
}

- (void)updateTileView:(TileView*)tileView
{
    [self loadBeatLayer:tileView.beatLayer];
    [self loadMarkLayer:tileView.markLayer];
}

- (void)loadMarkLayer:(CALayer*)rootLayer
{
    [rootLayer.sublayers makeObjectsPerformSelector:@selector(removeFromSuperlayer)];
    [rootLayer setNeedsDisplay];

    if (_frames == 0 || _waveView == nil || _beatSample == nil || rootLayer.superlayer.frame.origin.x < 0) {
        return;
    }
    
    const double framesPerPixel = _frames / _waveView.frame.size.width;
    
    const CGFloat start = rootLayer.superlayer.frame.origin.x;
    const CGFloat width = rootLayer.frame.size.width;

    const unsigned long long frameOffset = floor(start * framesPerPixel);

    TrackListIterator* iter = nil;
    unsigned long long nextTrackFrame = [_trackList firstTrackFrame:&iter];

    while (nextTrackFrame != ULONG_LONG_MAX) {
        // A mark before our tile start frame needs to get skipped.
        if (frameOffset < nextTrackFrame) {
            const CGFloat x = floor((nextTrackFrame / framesPerPixel) - start);
            // We need to stop drawing when we reached the total width of our layer.
            if (x >= width) {
                break;
            }
            CALayer* markLayer = [CALayer layer];
            markLayer.drawsAsynchronously = YES;
            markLayer.backgroundColor = [_markerColor CGColor];
            markLayer.frame = CGRectMake(x, 0, _markerWidth, _waveView.frame.size.height);
            [rootLayer addSublayer:markLayer];
        }

        nextTrackFrame = [_trackList nextTrackFrame:iter];
    };
}

- (void)loadBeatLayer:(CALayer*)rootLayer
{
    [rootLayer.sublayers makeObjectsPerformSelector:@selector(removeFromSuperlayer)];
    [rootLayer setNeedsDisplay];

    if (_frames == 0 || _waveView == nil || _beatSample == nil || rootLayer.superlayer.frame.origin.x < 0) {
        return;
    }
    
    const double framesPerPixel = _frames / _waveView.frame.size.width;
    
    const CGFloat start = rootLayer.superlayer.frame.origin.x;
    const CGFloat width = rootLayer.frame.size.width;

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
        [_beatSample getBeat:&currentEvent
                          at:currentBeatIndex];

        currentBeatIndex++;

        const CGFloat x = floor((currentEvent.frame / framesPerPixel) - start);
        
        // We need to stop drawing when we reached the total width of our layer.
        if (x >= width) {
            break;
        }

        if ((currentEvent.style & _beatMask) == 0) {
            continue;
        }
        
        CGColorRef color;
        CGFloat width;

        if ((currentEvent.style & BeatEventMaskMarkers) != 0) {
            color = [_markerColor CGColor];
            width = _markerWidth;
        } else if ((currentEvent.style & BeatEventStyleBar) == BeatEventStyleBar) {
            color = [_barColor CGColor];
            width = _barWidth;
        } else {
            color = [_beatColor CGColor];
            width = _beatWidth;
        }

        CALayer* beatLayer = [CALayer layer];
        beatLayer.drawsAsynchronously = YES;
        beatLayer.backgroundColor = color;
        beatLayer.frame = CGRectMake(x, 0, width, _waveView.frame.size.height);
        [rootLayer addSublayer:beatLayer];
    };
}

- (void)setTrackList:(TrackList *)trackList
{
    if (trackList  == _trackList) {
        return;
    }
    _trackList = trackList;
    assert(self.waveView.frame.size.width > 0);
}

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
    if (_visualSample == nil || layer.superlayer.frame.origin.x < 0) {
        return;
    }
    
    assert(layer.frame.size.width < 512);

    /*
      We try to fetch visual data first;
       - when that fails, we draw a box and trigger a task preparing visual data
       - when that works, we draw it
     */
    CGContextSetAllowsAntialiasing(context, YES);
    CGContextSetShouldAntialias(context, YES);

    const unsigned long int start = layer.superlayer.frame.origin.x;
    unsigned long int samplePairCount = layer.bounds.size.width + 1;

    // Try to get visual sample data for this layer tile.
    NSData* buffer = [_visualSample visualsFromOrigin:start];

    if (buffer == nil) {
        // We didnt find any visual data - lets make sure we get some in the near future...
        CGContextSetFillColorWithColor(context, _waveFillColor.CGColor);
        CGContextFillRect(context, layer.bounds);
        
        if (start >= _visualSample.width) {
            return;
        }
        
        [_visualSample prepareVisualsFromOrigin:start
                                          pairs:samplePairCount
                                         window:_offsetBlock()
                                          total:_widthBlock()
                                       callback:^(void){
            dispatch_async(dispatch_get_main_queue(), ^{
                [layer setNeedsDisplay];
            });
        }];
        return;
    }

    VisualPair* data = (VisualPair*)buffer.bytes;
    
    if (buffer.length / sizeof(VisualPair) < samplePairCount) {
        // We might have gotten less data than requested, accomodate.
        samplePairCount = buffer.length / sizeof(VisualPair);
    }

    CGFloat mid = floor(layer.bounds.size.height / 2.0);
    assert(mid > 0.01);
    CGFloat tops[samplePairCount];
    CGFloat bottoms[samplePairCount];
    
    for (unsigned int sampleIndex = 0; sampleIndex < samplePairCount; sampleIndex++) {
        //assert(data[sampleIndex].negativeAverage != NAN);
        assert(!isnan(data[sampleIndex].negativeAverage));
        CGFloat top = (mid + ((data[sampleIndex].negativeAverage * layer.bounds.size.height) / 2.0)) - 2.0;
        assert(!isnan(top));
        assert(!isnan(data[sampleIndex].positiveAverage));
        CGFloat bottom = (mid + ((data[sampleIndex].positiveAverage * layer.bounds.size.height) / 2.0)) + 2.0;
        assert(!isnan(bottom));
        tops[sampleIndex] = top;
        bottoms[sampleIndex] = bottom;
    }

//    CGContextSetFillColorWithColor(context, [[NSColor blueColor] CGColor]);
//    CGContextFillRect(context, layer.frame);

    CGContextSetFillColorWithColor(context, _waveFillColor.CGColor);

    CGContextSetLineCap(context, kCGLineCapRound);
    CGContextSetLineJoin(context, kCGLineJoinRound);

    CGFloat lineWidth = 4.0;
    CGFloat aliasingWidth = 2.0;
    CGFloat outlineWidth = 4.0;

    // Draw aliasing curve.
    CGContextSetLineWidth(context, lineWidth + outlineWidth + aliasingWidth);
    CGContextSetStrokeColorWithColor(context, [[_waveFillColor colorWithAlphaComponent:0.45f] CGColor]);
    for (unsigned int sampleIndex = 0; sampleIndex < samplePairCount; sampleIndex++) {
        CGContextMoveToPoint(context, sampleIndex, tops[sampleIndex]);
        CGContextAddLineToPoint(context, sampleIndex, bottoms[sampleIndex]);
    }
    CGContextStrokePath(context);
    
    // Draw outline curve.
    CGContextSetLineWidth(context, lineWidth + outlineWidth);
    CGContextSetStrokeColorWithColor(context, _waveOutlineColor.CGColor);
    for (unsigned int sampleIndex = 0; sampleIndex < samplePairCount; sampleIndex++) {
        CGContextMoveToPoint(context, sampleIndex, tops[sampleIndex]);
        CGContextAddLineToPoint(context, sampleIndex, bottoms[sampleIndex]);
    }
    CGContextStrokePath(context);

    // Draw fill curve.
    CGContextSetLineWidth(context, lineWidth);
    CGContextSetStrokeColorWithColor(context, _waveFillColor.CGColor);
    for (unsigned int sampleIndex = 0; sampleIndex < samplePairCount; sampleIndex++) {
        CGContextMoveToPoint(context, sampleIndex, tops[sampleIndex]);
        CGContextAddLineToPoint(context, sampleIndex, bottoms[sampleIndex]);
    }
    CGContextStrokePath(context);
}
@end
