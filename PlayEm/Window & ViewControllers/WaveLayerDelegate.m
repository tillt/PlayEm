//
//  WaveLayerDelegate.m
//  PlayEm
//
//  Created by Till Toenshoff on 25.08.23.
//  Copyright © 2023 Till Toenshoff. All rights reserved.
//

#import "WaveLayerDelegate.h"
#import "VisualSample.h"
#import "VisualPair.h"

@implementation WaveLayerDelegate
{
}

#pragma mark Layer delegate

- (void)drawLayer:(CALayer*)layer inContext:(CGContextRef)context
{
    if (_visualSample == nil || layer.frame.origin.x < 0) {
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

    const unsigned long int start = layer.frame.origin.x;
    unsigned long int samplePairCount = layer.bounds.size.width + 1;

    // Try to get visual sample data for this layer tile.
    NSData* buffer = [_visualSample visualsFromOrigin:start];

    if (buffer == nil) {
        // We didnt find any visual data - lets make sure we get some in the near future...
        CGContextSetFillColorWithColor(context, self.fillColor.CGColor);
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

    CGContextSetFillColorWithColor(context, self.fillColor.CGColor);

    CGContextSetLineCap(context, kCGLineCapRound);
    CGContextSetLineJoin(context, kCGLineJoinRound);

    CGFloat lineWidth = 4.0;
    CGFloat aliasingWidth = 2.0;
    CGFloat outlineWidth = 4.0;

    // Draw aliasing curve.
    CGContextSetLineWidth(context, lineWidth + outlineWidth + aliasingWidth);
    CGContextSetStrokeColorWithColor(context, [[self.fillColor colorWithAlphaComponent:0.45f] CGColor]);
    for (unsigned int sampleIndex = 0; sampleIndex < samplePairCount; sampleIndex++) {
        CGContextMoveToPoint(context, sampleIndex, tops[sampleIndex]);
        CGContextAddLineToPoint(context, sampleIndex, bottoms[sampleIndex]);
    }
    CGContextStrokePath(context);
    
    // Draw outline curve.
    CGContextSetLineWidth(context, lineWidth + outlineWidth);
    CGContextSetStrokeColorWithColor(context, self.outlineColor.CGColor);
    for (unsigned int sampleIndex = 0; sampleIndex < samplePairCount; sampleIndex++) {
        CGContextMoveToPoint(context, sampleIndex, tops[sampleIndex]);
        CGContextAddLineToPoint(context, sampleIndex, bottoms[sampleIndex]);
    }
    CGContextStrokePath(context);

    // Draw fill curve.
    CGContextSetLineWidth(context, lineWidth);
    CGContextSetStrokeColorWithColor(context, self.fillColor.CGColor);
    for (unsigned int sampleIndex = 0; sampleIndex < samplePairCount; sampleIndex++) {
        CGContextMoveToPoint(context, sampleIndex, tops[sampleIndex]);
        CGContextAddLineToPoint(context, sampleIndex, bottoms[sampleIndex]);
    }
    CGContextStrokePath(context);
}

@end
