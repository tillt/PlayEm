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

const double kFontSize = 11.0f;

@implementation TableCellView

+ (CIFilter*)sharedBloomFilter
{
    static dispatch_once_t once;
    static CIFilter* sharedInstance;
    dispatch_once(&once, ^{
        sharedInstance = [CIFilter filterWithName:@"CIBloom"];
        [sharedInstance setDefaults];
        [sharedInstance setValue:[NSNumber numberWithFloat:3.0] 
                          forKey: @"inputRadius"];
        [sharedInstance setValue:[NSNumber numberWithFloat:1.0] 
                          forKey: @"inputIntensity"];
    });
    return sharedInstance;
}

- (id)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.autoresizingMask = NSViewHeightSizable | NSViewWidthSizable;
        self.clipsToBounds = YES;
        self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;
    }
    return self;
}

- (CALayer*)makeBackingLayer
{
    CALayer* layer = [CALayer layer];
    layer.masksToBounds = NO;
    layer.autoresizingMask = kCALayerWidthSizable;
    layer.frame = self.bounds;

    _textLayer = [CATextLayer layer];
    _textLayer.fontSize = kFontSize;
    _textLayer.font =  (__bridge  CFTypeRef)[NSFont systemFontOfSize:kFontSize weight:NSFontWeightMedium];
    _textLayer.wrapped = NO;
    _textLayer.autoresizingMask = kCALayerWidthSizable;
    _textLayer.truncationMode = kCATruncationEnd;
    _textLayer.allowsEdgeAntialiasing = YES;
    _textLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    _textLayer.foregroundColor = [NSColor secondaryLabelColor].CGColor;
    _textLayer.frame = NSInsetRect(self.bounds, 0.0, 5.0);
    [layer addSublayer:_textLayer];

    _effectLayer = [CALayer layer];
    _effectLayer.backgroundFilters = @[ [TableCellView sharedBloomFilter] ];
    _effectLayer.anchorPoint = CGPointMake(0.5, 0.5);
    _effectLayer.masksToBounds = NO;
    _effectLayer.autoresizingMask = kCALayerWidthSizable;
    _effectLayer.zPosition = 1.9;
    _effectLayer.mask = [CAShapeLayer MaskLayerFromRect:self.bounds];
    _effectLayer.frame = self.bounds;
    _effectLayer.hidden = YES;
    [layer addSublayer:_effectLayer];
    
    return layer;
}

- (void)setExtraState:(ExtraState)extraState
{
    _extraState = extraState;
}

- (void)setBackgroundStyle:(NSBackgroundStyle)backgroundStyle
{
    CATextLayer* textLayer = (CATextLayer*)self.layer.sublayers[0];
    CALayer* effectLayer = self.layer.sublayers[1];
    
    NSColor* color = nil;
    BOOL effectsHidden = NO;

    switch (backgroundStyle) {
        case NSBackgroundStyleNormal:
            effectsHidden = YES;
            color = [NSColor secondaryLabelColor];
            break;
        case NSBackgroundStyleEmphasized:
            color = [NSColor labelColor];
            effectsHidden = YES;
            break;
        case NSBackgroundStyleRaised:
            color = [NSColor linkColor];
            effectsHidden = NO;
            break;
        case NSBackgroundStyleLowered:
            color = [NSColor linkColor];
            effectsHidden = NO;
            break;
    }

    if (_extraState == kExtraStateActive) {
        color = [[Defaults sharedDefaults] lightBeamColor];
        effectsHidden = NO;
    }

    textLayer.foregroundColor = color.CGColor;
    effectLayer.hidden = effectsHidden;
    
//    if (animate) {
//        NSMutableArray* animations = [NSMutableArray array];
//        CABasicAnimation* animation = [CABasicAnimation animationWithKeyPath:@"foregroundColor"];
//        animation.duration = 1.0;
//        animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
//        animation.fromValue = (id)[[[Defaults sharedDefaults] lightBeamColor] CGColor];
//        animation.toValue = (id)[[NSColor labelColor] CGColor];
//        animation.autoreverses = YES;
//        [animations addObject:animation];
//
//        CAAnimationGroup* group = [CAAnimationGroup animation];
//        group.animations = animations;
//        group.duration = 2.0;
//        group.repeatCount = HUGE_VALF;
//        group.autoreverses = YES;
//        group.removedOnCompletion = NO;
//        group.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
//        
//        [textLayer addAnimation:group forKey:@"test"];
//    } else {
//        [textLayer removeAllAnimations];
//    }
}

@end
