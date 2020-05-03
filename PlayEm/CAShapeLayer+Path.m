//
//  CAShapeLayer+Path.m
//  PlayEm
//
//  Created by Till Toenshoff on 23.10.22.
//  Copyright © 2022 Till Toenshoff. All rights reserved.
//

#import "CAShapeLayer+Path.h"
#import "NSBezierPath+CGPath.h"

@implementation CAShapeLayer (Path)

+ (CAShapeLayer*)MaskLayerFromRect:(NSRect)rect
{
    CAShapeLayer* maskLayer = [CAShapeLayer layer];
    maskLayer.fillRule = kCAFillRuleEvenOdd;
    NSBezierPath* path = [NSBezierPath bezierPath];
    [path appendBezierPathWithRect:rect];
    CGPathRef p = [NSBezierPath CGPathFromPath:path];
    maskLayer.path = p;
    CGPathRelease(p);
    return maskLayer;
}

@end
