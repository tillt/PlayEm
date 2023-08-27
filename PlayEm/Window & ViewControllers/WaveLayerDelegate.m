//
//  WaveLayerDelegate.m
//  PlayEm
//
//  Created by Till Toenshoff on 25.08.23.
//  Copyright © 2023 Till Toenshoff. All rights reserved.
//

#import "WaveLayerDelegate.h"
#import "VisualSample.h"

@implementation WaveLayerDelegate
{
}

#pragma mark Layer delegate

- (void)drawLayer:(CALayer *)layer inContext:(CGContextRef)context
{
    if (_visualSample == nil || layer.frame.origin.x < 0) {
        return;
    }

    /*
      We try to fetch visual data first;
       - when that fails, we draw a box and trigger a task preparing visual data
       - when that works, we draw it
     */
    CGContextSetAllowsAntialiasing(context, YES);
    CGContextSetShouldAntialias(context, YES);

    CGContextSetLineCap(context, kCGLineCapRound);
    unsigned long int start = layer.frame.origin.x;
    unsigned long int samplePairCount = layer.bounds.size.width + 1;

    NSData* buffer = nil;

    buffer = [_visualSample visualsFromOrigin:start];

    if (buffer != nil) {
        CGContextSetFillColorWithColor(context, [[NSColor clearColor] CGColor]);
        CGContextFillRect(context, layer.bounds);

        VisualPair* data = (VisualPair*)buffer.bytes;
        assert(samplePairCount == buffer.length / sizeof(VisualPair));

        CGContextSetLineWidth(context, 7.0f);
        CGContextSetStrokeColorWithColor(context, [[self.color colorWithAlphaComponent:0.40f] CGColor]);
        
        CGFloat mid = floor(layer.bounds.size.height / 2.0);

        for (unsigned int sampleIndex = 0; sampleIndex < samplePairCount; sampleIndex++) {
            CGFloat top = (mid + ((data[sampleIndex].negativeAverage * layer.bounds.size.height) / 2.0)) - 2.0;
            CGFloat bottom = (mid + ((data[sampleIndex].positiveAverage * layer.bounds.size.height) / 2.0)) + 2.0;

            CGContextMoveToPoint(context, sampleIndex, top);
            CGContextAddLineToPoint(context, sampleIndex, bottom);
            CGContextStrokePath(context);
        }

        CGContextSetLineWidth(context, 1.5);
        CGContextSetStrokeColorWithColor(context, self.color.CGColor);
        
        for (unsigned int sampleIndex = 0; sampleIndex < samplePairCount; sampleIndex++) {
            CGFloat top = (mid + ((data[sampleIndex].negativeAverage * layer.bounds.size.height) / 2.0)) - 1.0;
            CGFloat bottom = (mid + ((data[sampleIndex].positiveAverage * layer.bounds.size.height) / 2.0)) + 1.0;

            CGContextMoveToPoint(context, sampleIndex, top);
            CGContextAddLineToPoint(context, sampleIndex, bottom);
            CGContextStrokePath(context);
        }
    } else {
        CGContextSetFillColorWithColor(context, self.color.CGColor);
        CGContextFillRect(context, layer.bounds);

        if (start >= _visualSample.width) {
            return;
        }
        
        [_visualSample prepareVisualsFromOrigin:start
                                          width:samplePairCount
                                         window:_offsetBlock()
                                          total:_widthBlock()
                                       callback:^(void){
            [layer setNeedsDisplay];
        }];
    }
}

@end
