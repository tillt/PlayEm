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
    _textLayer.foregroundColor = [NSColor secondaryLabelColor].CGColor;
    _textLayer.frame = NSInsetRect(self.bounds, 0.0, 5.0);
    [layer addSublayer:_textLayer];
   
    return layer;
}

- (void)updatedStyle
{
    NSColor* color = nil;

    switch (self.backgroundStyle) {
        case NSBackgroundStyleNormal:
            color = [NSColor secondaryLabelColor];
            break;
        case NSBackgroundStyleEmphasized:
            color = [NSColor labelColor];
            break;
        case NSBackgroundStyleRaised:
            color = [NSColor linkColor];
            break;
        case NSBackgroundStyleLowered:
            color = [NSColor linkColor];
            break;
    }

    if (_extraState == kExtraStateActive) {
        color = [[Defaults sharedDefaults] lightBeamColor];
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

@end
