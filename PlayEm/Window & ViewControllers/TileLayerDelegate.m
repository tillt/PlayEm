//
//  WaveLayerDelegate.m
//  PlayEm
//
//  Created by Till Toenshoff on 25.08.23.
//  Copyright © 2023 Till Toenshoff. All rights reserved.
//
#import <CoreFoundation/CoreFoundation.h>
#import "TileLayerDelegate.h"

@implementation TileLayerDelegate
{
}

#pragma mark Layer delegate

- (void)drawLayer:(CALayer *)layer inContext:(CGContextRef)context
{
    CGContextSetAllowsAntialiasing(context, YES);
    CGContextSetShouldAntialias(context, YES);
    
    // Parameters

    CGFloat margin = 10;
    NSColor* color =  [NSColor whiteColor];
    CGFloat fontSize = 32;
    // You can use the Font Book app to find the name
    //NSString* fontName = @"Chalkboard";
//    CTFontRef font = CTFontCreateWithName((__bridge CFStringRef)fontName,
//                                          fontSize,
//                                          nil);
    
    NSFont* font = [NSFont fontWithName:@"Chalkboard" size:12.0];

    NSDictionary* attributes = @{
                     NSFontAttributeName : font,
          NSForegroundColorAttributeName : color
    };

    // Text
    NSString* string = @"The lazy fox…";
    NSAttributedString* attributedString = [[NSAttributedString alloc] initWithString:string attributes:attributes];

    // Render
    CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)attributedString);
    CGRect stringRect = CTLineGetImageBounds(line, context);

//    context.textPosition = CGMakePoint(bounds.maxX - stringRect.width - margin,
//                                       bounds.minY + margin);

    CTLineDraw(line, context);

//    /*
//      We try to fetch visual data first;
//       - when that fails, we draw a box and trigger a task preparing visual data
//       - when that works, we draw it
//     */
//
//    const unsigned long int start = layer.frame.origin.x;
//    const unsigned long int samplePairCount = layer.bounds.size.width + 1;
//
//    // Try to get visual sample data for this layer tile.
//    NSData* buffer = [_visualSample visualsFromOrigin:start];
//
//    if (buffer == nil) {
//        // We didnt find any visual data - lets make sure we get some in the near future...
//        CGContextSetFillColorWithColor(context, self.fillColor.CGColor);
//        CGContextFillRect(context, layer.bounds);
//        
//        if (start >= _visualSample.width) {
//            return;
//        }
//        
//        [_visualSample prepareVisualsFromOrigin:start
//                                          width:samplePairCount
//                                         window:_offsetBlock()
//                                          total:_widthBlock()
//                                       callback:^(void){
//            dispatch_async(dispatch_get_main_queue(), ^{
//                [layer setNeedsDisplay];
//            });
//        }];
//        return;
//    }
//
//    VisualPair* data = (VisualPair*)buffer.bytes;
//    assert(samplePairCount == buffer.length / sizeof(VisualPair));
//
//    CGFloat mid = floor(layer.bounds.size.height / 2.0);
//
//    CGFloat tops[samplePairCount];
//    CGFloat bottoms[samplePairCount];
//    
//    for (unsigned int sampleIndex = 0; sampleIndex < samplePairCount; sampleIndex++) {
//        CGFloat top = (mid + ((data[sampleIndex].negativeAverage * layer.bounds.size.height) / 2.0)) - 2.0;
//        CGFloat bottom = (mid + ((data[sampleIndex].positiveAverage * layer.bounds.size.height) / 2.0)) + 2.0;
//        
//        tops[sampleIndex] = top;
//        bottoms[sampleIndex] = bottom;
//    }
//
//    CGContextSetLineCap(context, kCGLineCapRound);
//    CGContextSetLineJoin(context, kCGLineJoinRound);
//
//    CGFloat lineWidth = 4.0;
//    CGFloat aliasingWidth = 2.0;
//    CGFloat outlineWidth = 4.0;
//
//    // Draw aliasing curve.
//    CGContextSetLineWidth(context, lineWidth + outlineWidth + aliasingWidth);
//    CGContextSetStrokeColorWithColor(context, [[self.fillColor colorWithAlphaComponent:0.45f] CGColor]);
//    for (unsigned int sampleIndex = 0; sampleIndex < samplePairCount; sampleIndex++) {
//        CGContextMoveToPoint(context, sampleIndex, tops[sampleIndex]);
//        CGContextAddLineToPoint(context, sampleIndex, bottoms[sampleIndex]);
//    }
//    CGContextStrokePath(context);
//    
//    // Draw outline curve.
//    CGContextSetLineWidth(context, lineWidth + outlineWidth);
//    CGContextSetStrokeColorWithColor(context, self.outlineColor.CGColor);
//    for (unsigned int sampleIndex = 0; sampleIndex < samplePairCount; sampleIndex++) {
//        CGContextMoveToPoint(context, sampleIndex, tops[sampleIndex]);
//        CGContextAddLineToPoint(context, sampleIndex, bottoms[sampleIndex]);
//    }
//    CGContextStrokePath(context);
//
//    // Draw fill curve.
//    CGContextSetLineWidth(context, lineWidth);
//    CGContextSetStrokeColorWithColor(context, self.fillColor.CGColor);
//    for (unsigned int sampleIndex = 0; sampleIndex < samplePairCount; sampleIndex++) {
//        CGContextMoveToPoint(context, sampleIndex, tops[sampleIndex]);
//        CGContextAddLineToPoint(context, sampleIndex, bottoms[sampleIndex]);
//    }
//    CGContextStrokePath(context);
}

@end
