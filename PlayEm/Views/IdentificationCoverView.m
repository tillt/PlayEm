//
//  IdentificationActiveView.m
//  PlayEm
//
//  Created by Till Toenshoff on 10.06.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import "IdentificationCoverView.h"
#import <Quartz/Quartz.h>
#import "../Sample/BeatEvent.h"
#import "CAShapeLayer+Path.h"
#import "CALayer+PauseAnimations.h"

static NSString * const kLayerImageName = @"IdentificationActiveStill";
static NSString * const kLayerMaskImageName = @"IdentificationActiveStill";

extern NSString * const kBeatTrackedSampleTempoChangeNotification;

@interface IdentificationCoverView ()
@property (nonatomic, strong) CALayer* imageLayer;
@property (nonatomic, strong) CALayer* imageLayer2;
@property (nonatomic, strong) CALayer* imageCopyLayer;
@property (nonatomic, strong) CALayer* maskLayer;
@property (nonatomic, strong) CALayer* overlayLayer;
@end

@implementation IdentificationCoverView
{
    float currentTempo;
    BOOL animating;
    BOOL paused;
}

- (id)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        animating = NO;
        paused = NO;
        currentTempo = 120.0f;
        _overlayIntensity = 0.3f;
        _sepiaForSecondImageLayer = YES;
        _secondImageLayerOpacity = 0.2;
        self.wantsLayer = YES;
        self.autoresizingMask = NSViewHeightSizable | NSViewWidthSizable;
        self.clipsToBounds = YES;
        self.layerUsesCoreImageFilters = YES;
        self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(tempoChange:) name:kBeatTrackedSampleTempoChangeNotification object:nil];
        //[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(beatEffect:) name:kBeatTrackedSampleBeatNotification object:nil];
    }
    return self;
}

- (void)tempoChange:(NSNotification*)notification
{
    NSNumber* tempo = notification.object;
    float value = [tempo floatValue];
    if (value > 0.0) {
        currentTempo = value;
    }
}

//- (void)beatEffect:(NSNotification*)notification
//{
//    [CATransaction begin];
//    [CATransaction setDisableActions:YES];
//    CAAnimationGroup* group = [CAAnimationGroup new];
//    NSMutableArray* list = [NSMutableArray array];
//    
//    CABasicAnimation* animation = [CABasicAnimation animationWithKeyPath:@"opacity"];
//    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
//    animation.fillMode = kCAFillModeForwards;
//    animation.removedOnCompletion = NO;
//    NSAssert(currentTempo > 0.0, @"current tempo set to zero, that should never happen");
//    double phaseLength = 60.0f / self->currentTempo;
//    animation.duration = 0.0005;
//    animation.fromValue = @(0.0);
//    animation.toValue = @(1.0);
//    animation.repeatCount = 1.0f;
//    //[list addObject:animation];
//    
//    animation = [CABasicAnimation animationWithKeyPath:@"opacity"];
//    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
//    animation.fillMode = kCAFillModeForwards;
//    animation.removedOnCompletion = NO;
//    NSAssert(currentTempo > 0.0, @"current tempo set to zero, that should never happen");
//    animation.duration = 0.4;
//    animation.fromValue = @(1.0);
//    animation.toValue = @(0.0);
//    animation.repeatCount = 1.0f;
//    [list addObject:animation];
//    group.animations = list;
//    //[_imageLayer addAnimation:group forKey:@"transparency"];
//    [_imageLayer addAnimation:animation forKey:@"transparency"];
//    [CATransaction commit];
//}

- (CALayer*)makeBackingLayer
{
    CALayer* layer = [CALayer layer];
    layer.masksToBounds = NO;
    layer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    layer.frame = self.bounds;

    _maskLayer = [CALayer layer];
    _maskLayer.frame = CGRectMake(-self.bounds.size.width / 2, -self.bounds.size.height / 2, self.bounds.size.width * 2, self.bounds.size.height * 2);
    _maskLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    _maskLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    _maskLayer.allowsEdgeAntialiasing = YES;
    _maskLayer.position = CGPointMake(self.bounds.size.width / 2, self.bounds.size.height / 2);
    _maskLayer.contents = [NSImage imageNamed:@"FadeMask"];;

    _imageCopyLayer = [CALayer layer];
    _imageCopyLayer.frame = self.bounds;
    _imageCopyLayer.contents = [NSImage imageNamed:@"UnknownSong"];
    _imageCopyLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    _imageCopyLayer.allowsEdgeAntialiasing = YES;
    _imageCopyLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    _imageCopyLayer.frame = NSInsetRect(self.bounds, 0.0, 0.0);
    _imageCopyLayer.mask = _maskLayer;
    _imageCopyLayer.cornerRadius = 7;

    CIFilter* additionFilter = [CIFilter filterWithName:@"CIAdditionCompositing"];
    [additionFilter setDefaults];
    
    if (_sepiaForSecondImageLayer) {
        CIFilter* sepia = [CIFilter filterWithName:@"CISepiaTone"];
        [sepia setDefaults];
        _imageCopyLayer.filters = @[ sepia ];
    }
    _imageCopyLayer.opacity = _secondImageLayerOpacity;
    [layer addSublayer:_imageCopyLayer];

    CIFilter* bloomFilter = [CIFilter filterWithName:@"CIBloom"];
    [bloomFilter setDefaults];
    [bloomFilter setValue: [NSNumber numberWithFloat:5.0] forKey: @"inputRadius"];
    [bloomFilter setValue: [NSNumber numberWithFloat:1.0] forKey: @"inputIntensity"];

    _imageLayer = [CALayer layer];
    _imageLayer.frame = self.bounds;
    _imageLayer.contents = [NSImage imageNamed:@"UnknownSong"];
    _imageLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    _imageLayer.allowsEdgeAntialiasing = YES;
    _imageLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    _imageLayer.frame = NSInsetRect(self.bounds, 0.0, 0.0);
    _imageLayer.mask = _maskLayer;
    _imageLayer.cornerRadius = 7;
    _imageLayer.filters = @[ bloomFilter     ];
    [layer addSublayer:_imageLayer];

    _overlayLayer = [CALayer layer];
    _overlayLayer.contents = [NSImage imageNamed:kLayerImageName];
    _overlayLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    _overlayLayer.allowsEdgeAntialiasing = YES;
    _overlayLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    _overlayLayer.opacity = _overlayIntensity;
    _overlayLayer.anchorPoint = CGPointMake(0.5, 0.507);
    _overlayLayer.frame = _maskLayer.frame;
    _overlayLayer.compositingFilter = additionFilter;
    [layer addSublayer:_overlayLayer];

    layer.masksToBounds = YES;

    return layer;
}

- (void)setImage:(NSImage*)image
{
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        [context setDuration:2.1f];
        [context setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn]];
        self.animator.imageCopyLayer.contents = image;
        self.animator.imageLayer.contents = image;
        self.animator.imageLayer2.contents = image;
    }];
}

- (void)animate
{
    const float beatsPerCycle = 4.0f;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
        CABasicAnimation* animation = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
        animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
        animation.fillMode = kCAFillModeForwards;
        animation.removedOnCompletion = NO;
        NSAssert(currentTempo > 0.0, @"current tempo set to zero, that should never happen");
        animation.duration = beatsPerCycle * 60.0f / self->currentTempo;
        const CGFloat angleToAdd = -M_PI_2 * beatsPerCycle;
        [_overlayLayer setValue:@(M_PI_2 * beatsPerCycle) forKeyPath:@"transform.rotation.z"];
        [_maskLayer setValue:@(M_PI_2 * beatsPerCycle) forKeyPath:@"transform.rotation.z"];
        animation.toValue = @(0.0);        // model value was already changed. End at that value
        animation.byValue = @(angleToAdd); // start from - this value (it's toValue - byValue (see above))
        animation.repeatCount = 1.0f;
        [CATransaction setCompletionBlock:^{
            if (!self->animating) {
                NSLog(@"we are not animating anymore!!!!");
                return;
            }
            [self animate];
        }];
        [_overlayLayer addAnimation:animation forKey:@"rotation"];
        [_maskLayer addAnimation:animation forKey:@"rotation"];
    [CATransaction commit];
}

- (void)startAnimating
{
    NSLog(@"start animating coverview with tempo %f", currentTempo);
    if (paused) {
        NSLog(@"coverview was paused, resume");
        [self resumeAnimating];
        return;
    }

    if (animating) {
        NSLog(@"coverview got this already");
        return;
    }

    [self animate];

    NSLog(@"we should be animating coverview");
    animating = YES;
}

- (void)stopAnimating
{
    paused = NO;
}

- (void)resumeAnimating
{
    [_overlayLayer resumeAnimating];
    [_maskLayer resumeAnimating];

    paused = NO;
}

- (void)pauseAnimating
{
    [_overlayLayer pauseAnimating];
    [_maskLayer pauseAnimating];

    paused = YES;
}

@end
