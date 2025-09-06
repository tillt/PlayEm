//
//  BloomyText.m
//  PlayEm
//
//  Created by Till Toenshoff on 9/6/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//
#import <CoreImage/CoreImage.h>
#import <QuartzCore/QuartzCore.h>
#import "../CAShapeLayer+Path.h"
#import "BloomyText.h"
#import "BeatEvent.h"

//extern NSString * const kAudioControllerChangedPlaybackStateNotification;
//extern NSString * const kPlaybackStateStarted;
//extern NSString * const kPlaybackStateEnded;
//extern NSString * const kPlaybackStatePaused;
//extern NSString * const kPlaybackStatePlaying;
static const NSTimeInterval kBeatEffectRampUp = 0.05f;
static const NSTimeInterval kBeatEffectRampDown = 0.9f;

@interface BloomyText()

@property (nonatomic, strong) CATextLayer* textLayer;
@property (nonatomic, strong) CALayer* fxLayer;
@property (nonatomic, strong, readonly) NSDictionary* attributes;
@property (nonatomic, strong) CIFilter* titleBloomFilter;
@property (nonatomic, strong) CATiledLayer* rastaLayer;

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
        
//        [[NSNotificationCenter defaultCenter] addObserver:self
//                                                 selector:@selector(audioControllerChangedPlaybackState:)
//                                                     name:kAudioControllerChangedPlaybackStateNotification
//                                                   object:nil];
//        [[NSNotificationCenter defaultCenter] addObserver:self
//                                                 selector:@selector(beatEffect:)
//                                                     name:kBeatTrackedSampleBeatNotification
//                                                   object:nil];

    }
    return self;
}

- (void)dealloc
{
}

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
//    layer.anchorPoint = CGPointMake(0.5, 0.5);
    return layer;
}

- (CATextLayer*)makeTextLayer
{
    CATextLayer* layer = [CATextLayer layer];
//    layer.anchorPoint = CGPointMake(1.0, 0.0);
//    layer.frame = self.bounds;
    layer.font = (__bridge  CFTypeRef)self.font;
    layer.fontSize = self.fontSize;
    layer.foregroundColor = _textColor.CGColor;
//    layer.backgroundColor = [NSColor whiteColor].CGColor;
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
    [bloomFilter setValue: [NSNumber numberWithFloat:7.0] forKey: @"inputRadius"];
    [bloomFilter setValue: [NSNumber numberWithFloat:0.8] forKey: @"inputIntensity"];

//    _titleBloomFilter = [CIFilter filterWithName:@"CIZoomBlur"];
//    [_titleBloomFilter setDefaults];
//    [_titleBloomFilter setValue: [NSNumber numberWithFloat:1.0] forKey: @"inputAmount"];
//    [_titleBloomFilter setValue: [CIVector vectorWithCGPoint:CGPointMake(self.textLayer.frame.size.width / 2.0, self.textLayer.frame.size.height / 2.0)] forKey: @"inputCenter"];

    self.fxLayer = [CALayer layer];
    _fxLayer.backgroundFilters = @[ bloomFilter];
    _fxLayer.frame = NSInsetRect(self.bounds, -16, -16);
    _fxLayer.masksToBounds = NO;
    _fxLayer.mask = [CAShapeLayer MaskLayerFromRect:_fxLayer.bounds];


    self.rastaLayer = [CATiledLayer layer];
    _rastaLayer.backgroundColor = [[NSColor colorWithPatternImage:[NSImage imageNamed:@"RastaPattern"]] CGColor];
    _rastaLayer.contentsScale = NSViewLayerContentsPlacementScaleProportionallyToFill;
    _rastaLayer.anchorPoint = CGPointMake(1.0, 0.0);
    _rastaLayer.autoresizingMask = kCALayerWidthSizable;
    _rastaLayer.frame = NSMakeRect(self.bounds.origin.x,
                                   self.bounds.origin.y,
                                   self.bounds.size.width + 100.0,
                                   self.bounds.size.height);
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
    return @{ NSForegroundColorAttributeName:_textColor,
              NSFontAttributeName: _font    };
}

- (void)setText:(NSString *)text
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

- (void)beatEffect:(id)sender
{
//    CAAnimationGroup *group = [[CAAnimationGroup alloc] init];
//    NSMutableArray* animations = [NSMutableArray array];
    CABasicAnimation* animation;
    
    float scale = 1.05;
    
    CATransform3D tr = CATransform3DIdentity;

    //CGFloat halfWidth = 0.0;

    CGFloat halfWidth = _textLayer.frame.size.width / 2.0;
    CGFloat halfHeight = _textLayer.frame.size.height / 2.0;

//    animation = [CABasicAnimation animationWithKeyPath:@"transform"];
//
//    tr = CATransform3DTranslate(tr, halfWidth, halfHeight, 0.0);
//    tr = CATransform3DScale(tr, scale, scale, 1.0);
//    tr = CATransform3DTranslate(tr, -halfWidth, -halfHeight, 0.0);
//
////    animation.fromValue = [NSValue valueWithCATransform3D:CATransform3DIdentity];
//    animation.fromValue = [NSValue valueWithCATransform3D:tr];
//
//    tr = CATransform3DIdentity;
//
//    animation.toValue = [NSValue valueWithCATransform3D:tr];
//    animation.repeatCount = 1.0f;
//    animation.autoreverses = YES;
//    animation.duration = kBeatEffectRampDown / 2.0;
//    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
//    animation.fillMode = kCAFillModeBoth;
//    animation.removedOnCompletion = NO;
//    [_textLayer addAnimation:animation forKey:@"beatScaling"];
//    _textLayer.transform = tr;

//    animation = [CABasicAnimation animationWithKeyPath:@"foregroundColor"];
//
//    animation.fromValue = (id)_lightTextColor.CGColor;
//    animation.toValue = (id)_textColor.CGColor;
//    animation.repeatCount = 1.0f;
//    animation.autoreverses = NO;
//    animation.duration = kBeatEffectRampDown;
//    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
//    animation.fillMode = kCAFillModeBoth;
//    animation.removedOnCompletion = NO;
    //[animations addObject:animation];
//    [_textLayer addAnimation:animation forKey:@"beatColor"];

//    animation = [CABasicAnimation animationWithKeyPath:@"backgroundFilters.CIZoomBlur.inputAmount"];
//    animation.fromValue = @(7.0);
//    animation.toValue = @(1.0);
//    animation.repeatCount = 1.0f;
//    animation.autoreverses = NO;
//    animation.duration = kBeatEffectRampDown;
//    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
//    animation.fillMode = kCAFillModeBoth;
//    animation.removedOnCompletion = NO;
//    //[animations addObject:animation];
//    [_fxLayer addAnimation:animation forKey:@"beatWarping"];

//    group.animations = animations;

}

@end
