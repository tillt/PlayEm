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
#import "BeatEvent.h"

static const double kFontSize = 11.0f;

@implementation TableCellView
{
}

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
    //layer.backgroundColor = [NSColor textBackgroundColor].CGColor;
    layer.opaque = NO;
    layer.frame = self.bounds;

    _textLayer = [CATextLayer layer];
    _textLayer.drawsAsynchronously = YES;
    _textLayer.fontSize = kFontSize;
    _textLayer.font =  (__bridge  CFTypeRef)[TableCellView sharedFont];
    _textLayer.wrapped = NO;
    //_textLayer.backgroundColor = [NSColor textBackgroundColor].CGColor;
    _textLayer.autoresizingMask = kCALayerWidthSizable;
    _textLayer.truncationMode = kCATruncationEnd;
    _textLayer.allowsEdgeAntialiasing = YES;
    _textLayer.masksToBounds = YES;
    _textLayer.opaque = NO;
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

// FIXME: These are far too expensive -- no idea why that is.
- (void)beatEffect:(NSNotification*)notification
{
    const NSDictionary* dict = notification.object;
    const unsigned int style = [dict[kBeatNotificationKeyStyle] intValue];
    const float tempo = [dict[kBeatNotificationKeyTempo] floatValue];
    const float barDuration = 4.0f * 60.0f / tempo;
    
    if ((style & BeatEventStyleBar) == BeatEventStyleBar) {
        // For creating a discrete effect accross the timeline, a keyframe animation is the
        // right thing as it even allows us to animate strings.
        {
            CAKeyframeAnimation* animation = [CAKeyframeAnimation animationWithKeyPath:@"foregroundColor"];
            animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
            
            //    animation.fromValue = (id)[[[Defaults sharedDefaults] lightBeamColor] CGColor];
            //animation.toValue = (id)[[NSColor secondaryLabelColor] CGColor];
            animation.values = @[ (id)[[[Defaults sharedDefaults] lightBeamColor] CGColor],
                                  (id)[[NSColor secondaryLabelColor] CGColor] ];
            animation.fillMode = kCAFillModeBoth;
            [animation setValue:@"barSyncedColor" forKey:@"name"];
            animation.removedOnCompletion = NO;
            animation.repeatCount = 1;
            // We animate throughout an entire bar.
            animation.duration = barDuration;
            [_textLayer addAnimation:animation forKey:@"barSynced"];
        }
    }
}

- (void)setBackgroundStyle:(NSBackgroundStyle)backgroundStyle
{
    [super setBackgroundStyle:backgroundStyle];
    [self updatedStyle];
}

@end
