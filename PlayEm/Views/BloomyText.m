//
//  BloomyText.m
//  PlayEm
//
//  Created by Till Toenshoff on 9/6/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//
#import "BloomyText.h"

#import <CoreImage/CoreImage.h>
#import <QuartzCore/QuartzCore.h>

#import "../CAShapeLayer+Path.h"

@interface BloomyText ()

@property (nonatomic, strong) CATextLayer* textLayer;
@property (nonatomic, strong) CALayer* fxLayer;
@property (nonatomic, strong, readonly) NSDictionary* attributes;
@property (nonatomic, strong) CIFilter* titleBloomFilter;
@property (nonatomic, strong) CALayer* rastaLayer;

@end

@implementation BloomyText

- (nonnull instancetype)initWithFrame:(CGRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.clipsToBounds = NO;
        self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;
        self.layerUsesCoreImageFilters = YES;
        self.layer = [self makeBackingLayer];
        self.layer.frame = frameRect;
    }
    return self;
}

- (void)dealloc
{}

- (BOOL)wantsLayer
{
    return YES;
}

- (BOOL)wantsUpdateLayer
{
    return YES;
}

- (CALayer*)makeBackingLayer
{
    CALayer* layer = [CALayer layer];
    layer.drawsAsynchronously = YES;
    return layer;
}

- (CATextLayer*)makeTextLayer
{
    CATextLayer* layer = [CATextLayer layer];
    layer.drawsAsynchronously = YES;
    layer.font = (__bridge CFTypeRef) self.font;
    layer.fontSize = self.fontSize;
    layer.allowsEdgeAntialiasing = YES;
    layer.allowsFontSubpixelQuantization = YES;
    layer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    layer.foregroundColor = _textColor.CGColor;
    return layer;
}

- (void)viewDidMoveToSuperview
{
    [super viewDidMoveToSuperview];

    self.textLayer = [self makeTextLayer];
    self.textLayer.string = _text;

    NSAttributedString* attributedString = [[NSAttributedString alloc] initWithString:self.text attributes:[self attributes]];
    self.textLayer.frame = CGRectMake(0.0, 0.0, attributedString.size.width, attributedString.size.height);

    CIFilter* bloomFilter = [CIFilter filterWithName:@"CIBloom"];
    [bloomFilter setDefaults];
    [bloomFilter setValue:[NSNumber numberWithFloat:7.0] forKey:@"inputRadius"];
    [bloomFilter setValue:[NSNumber numberWithFloat:0.8] forKey:@"inputIntensity"];

    //    _titleBloomFilter = [CIFilter filterWithName:@"CIZoomBlur"];
    //    [_titleBloomFilter setDefaults];
    //    [_titleBloomFilter setValue: [NSNumber numberWithFloat:1.0] forKey:
    //    @"inputAmount"];
    //    [_titleBloomFilter setValue: [CIVector
    //    vectorWithCGPoint:CGPointMake(self.textLayer.frame.size.width / 2.0,
    //    self.textLayer.frame.size.height / 2.0)] forKey: @"inputCenter"];

    self.fxLayer = [CALayer layer];
    _fxLayer.drawsAsynchronously = YES;
    _fxLayer.backgroundFilters = @[ bloomFilter ];
    _fxLayer.frame = NSInsetRect(self.bounds, -16, -16);
    _fxLayer.masksToBounds = NO;
    _fxLayer.mask = [CAShapeLayer MaskLayerFromRect:_fxLayer.bounds];

    self.rastaLayer = [CALayer layer];
    _rastaLayer.backgroundColor = [[NSColor colorWithPatternImage:[NSImage imageNamed:@"RastaPattern"]] CGColor];
    _rastaLayer.contentsScale = NSViewLayerContentsPlacementScaleProportionallyToFill;
    _rastaLayer.anchorPoint = CGPointMake(1.0, 0.0);
    _rastaLayer.drawsAsynchronously = YES;
    _rastaLayer.autoresizingMask = kCALayerWidthSizable;
    _rastaLayer.frame = NSMakeRect(self.bounds.origin.x, self.bounds.origin.y, self.bounds.size.width + 100.0, self.bounds.size.height);
    _rastaLayer.zPosition = 1.1;
    _rastaLayer.opacity = 0.4;
    _rastaLayer.compositingFilter = [CIFilter filterWithName:@"CISourceAtopCompositing"];

    [_textLayer addSublayer:_rastaLayer];
    [_textLayer addSublayer:_fxLayer];

    [self.layer addSublayer:_textLayer];

    CABasicAnimation* animation = [CABasicAnimation animationWithKeyPath:@"transform"];
    CATransform3D tr = CATransform3DIdentity;
    animation.fromValue = [NSValue valueWithCATransform3D:tr];
    tr = CATransform3DTranslate(tr, -4.0, 0.0, 0.0);
    animation.toValue = [NSValue valueWithCATransform3D:tr];
    animation.repeatCount = FLT_MAX;
    animation.autoreverses = NO;
    animation.duration = 0.2f;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    animation.fillMode = kCAFillModeBoth;
    animation.removedOnCompletion = NO;
    [_rastaLayer addAnimation:animation forKey:@"beatScaling"];
}

- (NSDictionary*)attributes
{
    return @{NSForegroundColorAttributeName : _textColor, NSFontAttributeName : _font};
}

- (void)setText:(NSString*)text
{
    if ([_text isEqualToString:text]) {
        return;
    }
    _text = text;

    [self setNeedsDisplay:YES];
}

- (void)setTextColor:(NSColor*)color
{
    if (color == _textColor) {
        return;
    }
    _textColor = color;

    [self setNeedsDisplay:YES];
}

@end
