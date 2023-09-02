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

- (void)drawLayer:(CALayer *)layer inContext:(CGContextRef)context
{
    if (_waveView == nil || _beatSample == nil || layer.frame.origin.x < 0) {
        return;
    }
    const double framesPerPixel = _beatSample.framesPerPixel;

    /*
      We try to fetch visual data first;
       - when that fails, we draw a box and trigger a task preparing visual data
       - when that works, we draw it
     */
    CGContextSetAllowsAntialiasing(context, YES);
    CGContextSetShouldAntialias(context, YES);

    CGContextSetLineCap(context, kCGLineCapRound);
    CGFloat start = layer.superlayer.frame.origin.x > 0 ? layer.superlayer.frame.origin.x : 0.0f;

    NSData* buffer = [_beatSample beatsFromOrigin:start];
    
    if (buffer != nil) {
        CGContextSetFillColorWithColor(context, [[NSColor clearColor] CGColor]);
        CGContextFillRect(context, layer.bounds);

        BeatEvent* events = (BeatEvent*)buffer.bytes;
        const float maxBeatCount = buffer.length / sizeof(BeatEvent);

        CGContextSetLineWidth(context, 2.5);
        
        //NSColor* beatColor = [[[Defaults sharedDefaults] regularBeamColor] colorWithAlphaComponent:0.4];
        
        for (unsigned int beatIndex = 0; beatIndex < maxBeatCount; beatIndex++) {
            const CGFloat x = (events[beatIndex].frame / framesPerPixel) - start;
            NSColor* beatColor = [[NSColor colorWithRed:1.00f green:0.540f blue:0.60f alpha:1.0f] colorWithAlphaComponent:0.4 * events[beatIndex].confidence];
            assert(x <= 256.0);
            CGContextSetStrokeColorWithColor(context, beatColor.CGColor);
            CGContextMoveToPoint(context, x, 0.0f);
            CGContextAddLineToPoint(context, x, layer.frame.size.height);
            CGContextStrokePath(context);
            //NSLog(@"drawing beat index %d: frame %lld (x:%f), bpm: %f, confidence: %f", beatIndex, events[beatIndex].frame, x, events[beatIndex].bpm, events[beatIndex].confidence);
        }
    } else {
        // Try again!
       // [layer setNeedsDisplay];
  //      NSLog(@"trying origin %ld again", start);

        //CGFloat offset = _waveView.enclosingScrollView.documentVisibleRect.origin.x;
        //CGFloat totalWidth = _waveView.enclosingScrollView.documentVisibleRect.size.width;

//        NSLog(@"preparing beats starting from %ld", start);
//        [_beatSample prepareBeatsFromOrigin:start callback:^(void){
//            // Once data is prepared, trigger a redraw - invoking `drawLayer:` again.
//            [layer setNeedsDisplay];
//            NSLog(@"calling for beats starting from %ld", start);
//        }];
    }
}

@end
