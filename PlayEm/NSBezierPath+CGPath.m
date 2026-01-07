//
//  NSBezierPath+CGPath.m
//  PlayEm
//
//  Created by Till Toenshoff on 16.10.22.
//  Copyright © 2022 Till Toenshoff. All rights reserved.
//

#import "NSBezierPath+CGPath.h"

@implementation NSBezierPath (CGPath)

+ (CGMutablePathRef)CGPathFromPath:(NSBezierPath*)path
{
    CGMutablePathRef cgPath = CGPathCreateMutable();
    NSInteger n = [path elementCount];

    for (NSInteger i = 0; i < n; i++) {
        NSPoint ps[3];
        switch ([path elementAtIndex:i associatedPoints:ps]) {
        case NSBezierPathElementMoveTo: {
            CGPathMoveToPoint(cgPath, NULL, ps[0].x, ps[0].y);
            break;
        }
        case NSBezierPathElementLineTo: {
            CGPathAddLineToPoint(cgPath, NULL, ps[0].x, ps[0].y);
            break;
        }
        case NSBezierPathElementCubicCurveTo: {
            CGPathAddCurveToPoint(cgPath, NULL, ps[0].x, ps[0].y, ps[1].x, ps[1].y, ps[2].x, ps[2].y);
            break;
        }
        case NSBezierPathElementClosePath: {
            CGPathCloseSubpath(cgPath);
            break;
        }
        default:
            NSAssert(0, @"Invalid NSBezierPathElement");
        }
    }
    return cgPath;
}

@end
