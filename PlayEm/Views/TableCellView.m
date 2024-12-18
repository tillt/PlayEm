//
//  TableCellView.m
//  PlayEm
//
//  Created by Till Toenshoff on 08.06.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import "TableCellView.h"
#import <Quartz/Quartz.h>
#import "CAShapeLayer+Path.h"
#import "Defaults.h"

static const double kFontSize = 11.0f;

@implementation TableCellView

+ (NSFont*)sharedFont
{
    static dispatch_once_t once;
    static NSFont* sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [NSFont systemFontOfSize:kFontSize weight:NSFontWeightMedium];
    });
    return sharedInstance;
}

- (id)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.needsLayout = YES;
        self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;
    }
    return self;
}

- (CALayer*)makeBackingLayer
{
    CALayer* layer = [CALayer layer];
    layer.masksToBounds = YES;
    layer.drawsAsynchronously = YES;
    layer.autoresizingMask = kCALayerNotSizable;
    layer.frame = self.bounds;

    _textLayer = [CATextLayer layer];
    _textLayer.drawsAsynchronously = YES;
    _textLayer.fontSize = kFontSize;
    _textLayer.font =  (__bridge  CFTypeRef)[TableCellView sharedFont];
    _textLayer.wrapped = NO;
    _textLayer.autoresizingMask = kCALayerWidthSizable;
    _textLayer.truncationMode = kCATruncationEnd;
    _textLayer.allowsEdgeAntialiasing = YES;
    _textLayer.masksToBounds = YES;
    _textLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    _textLayer.foregroundColor = [[Defaults sharedDefaults] secondaryLabelColor].CGColor;
    _textLayer.frame = NSInsetRect(self.bounds, 0.0, 5.0);
    [layer addSublayer:_textLayer];
   
    return layer;
}

- (void)updatedStyle
{
    NSColor* color = nil;

    if (_extraState == kExtraStateActive || _extraState == kExtraStatePlaying) {
        color = [[Defaults sharedDefaults] lightBeamColor];
    } else {
        switch (self.backgroundStyle) {
            case NSBackgroundStyleNormal:
                color = [[Defaults sharedDefaults] secondaryLabelColor];
                break;
            case NSBackgroundStyleEmphasized:
                color = [[Defaults sharedDefaults] lightBeamColor];
                break;
            case NSBackgroundStyleRaised:
            case NSBackgroundStyleLowered:
            default:
                color = [NSColor linkColor];
        }
    }
    _textLayer.foregroundColor = color.CGColor;
}

- (void)setExtraState:(ExtraState)extraState
{
    _extraState = extraState;
    [self updatedStyle];
}

- (void)setBackgroundStyle:(NSBackgroundStyle)backgroundStyle
{
    [super setBackgroundStyle:backgroundStyle];
    [self updatedStyle];
}

//- (CAAnimationGroup*)textColorAnimation
//{
//    CAAnimationGroup* group = [CAAnimationGroup animation];
//    NSMutableArray* animations = [NSMutableArray array];
//
//    CABasicAnimation* animation = [CABasicAnimation animationWithKeyPath:@"foregroundColor"];
//    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
//    animation.fromValue = (id)[[NSColor secondaryLabelColor] CGColor];
//    animation.toValue = (id)[[[Defaults sharedDefaults] lightBeamColor] CGColor];
//    animation.fillMode = kCAFillModeForwards;
//    animation.removedOnCompletion = NO;
//    [animation setValue:@"TextColorUp" forKey:@"name"];
//    animation.removedOnCompletion = NO;
//    animation.duration = 0.2;
//    [animations addObject:animation];
//
//    animation = [CABasicAnimation animationWithKeyPath:@"foregroundColor"];
//    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
//    animation.fromValue = (id)[[[Defaults sharedDefaults] lightBeamColor] CGColor];
//    animation.toValue = (id)[[NSColor secondaryLabelColor] CGColor];
//    animation.fillMode = kCAFillModeForwards;
//    animation.removedOnCompletion = NO;
//    animation.duration = 1.8;
//    [animation setValue:@"TextColorDown" forKey:@"name"];
//    [animations addObject:animation];
//
//    group.removedOnCompletion = NO;
//    group.animations = animations;
//    group.repeatCount = HUGE_VALF;
//    [group setValue:@"TextColorActiveAnimations" forKey:@"name"];
//
//    return group;
//}

@end
