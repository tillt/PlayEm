//
//  IdentificationActiveView.m
//  PlayEm
//
//  Created by Till Toenshoff on 10.06.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import "IdentificationCoverView.h"

#import <CoreImage/CIFilterBuiltins.h>
#import <CoreImage/CoreImage.h>
#import <Quartz/Quartz.h>

#import "../Audio/AudioProcessing.h"
#import "../Defaults.h"
#import "../NSBezierPath+CGPath.h"
#import "../NSImage+Average.h"
#import "../NSImage+Resize.h"
#import "CALayer+PauseAnimations.h"
#import "CAShapeLayer+Path.h"
#import "MediaMetaData.h"
#import "Sample/BeatEvent.h"

// #define HIDE_COVER_DEBBUG 1
// #define WITH_HELO 1

static NSString* const kLayerImageName = @"IdentificationActiveStill";
static NSString* const kLayerMaskImageName = @"IdentificationActiveStill";
extern NSString* const kBeatTrackedSampleTempoChangeNotification;

@interface IdentificationCoverView ()
@property (nonatomic, strong) CALayer* stillImageLayer;
@property (nonatomic, strong) CALayer* imageLayer;
@property (nonatomic, strong) CALayer* red;
@property (nonatomic, strong) CALayer* green;
@property (nonatomic, strong) CALayer* blue;
@property (nonatomic, strong) CALayer* imageCopyLayer;
@property (nonatomic, strong) CALayer* maskLayer;
@property (nonatomic, strong) CALayer* rotateLayer;
@property (nonatomic, strong) CALayer* overlayLayer;
@property (nonatomic, strong) CALayer* glowLayer;
@property (nonatomic, strong) CALayer* heloLayer;
//@property (nonatomic, strong) CALayer* glowMaskLayer;
@property (nonatomic, strong) CALayer* finalFxLayer;
@property (nonatomic, strong) CIFilter* bloomFilter;
@property (nonatomic, strong) CIFilter* clampFilter;
@property (nonatomic, assign) NSPoint rCurrent;
@property (nonatomic, assign) NSPoint gCurrent;
@property (nonatomic, assign) NSPoint bCurrent;

@end

@implementation IdentificationCoverView {
    float currentTempo;
    BOOL animating;
    BOOL paused;
    BOOL unknown;
    BOOL used;
    double lastEnergy;
    int moveBeats;
}

- (id)initWithFrame:(NSRect)frameRect contentsInsets:(NSEdgeInsets)insets style:(CoverViewStyleMask)style
{
    self = [super initWithFrame:frameRect];
    if (self) {
        animating = NO;
        paused = NO;
        used = NO;
        unknown = YES;
        currentTempo = 120.0f;
        lastEnergy = 0.0;
        moveBeats = 4;
        _overlayIntensity = 0.5f;
        _secondImageLayerOpacity = 1.0;
        _style = style;
        _rCurrent = NSZeroPoint;
        _gCurrent = NSZeroPoint;
        _bCurrent = NSZeroPoint;

        self.additionalSafeAreaInsets = insets;
        self.wantsLayer = YES;
        self.autoresizingMask = NSViewHeightSizable | NSViewWidthSizable;
        self.clipsToBounds = NO;
        self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;
        self.layerUsesCoreImageFilters = YES;

        if ((style & CoverViewStylePumpingToTheBeat) == CoverViewStylePumpingToTheBeat) {
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(beatEffect:) name:kBeatTrackedSampleBeatNotification object:nil];
        }
        if ((style & CoverViewStyleRotatingLaser) == CoverViewStyleRotatingLaser) {
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(tempoChange:) name:kBeatTrackedSampleTempoChangeNotification object:nil];
        }
    }
    return self;
}

- (BOOL)allowsVibrancy
{
    return YES;
}
- (void)beatPumpingLayer:(CALayer*)layer localEnergy:(double)localEnergy totalEnergy:(double)totalEnergy
{
    const CGSize halfSize = CGSizeMake(layer.bounds.size.width / 2.0, layer.bounds.size.height / 2.0);

    if (localEnergy == 0.0) {
        localEnergy = 0.000000001;
    }
    const double depth = 7.3;
    // Attempt to get a reasonably wide signal range by normalizing the local
    // peaks by the globally most energy loaded samples.
    const double normalizedEnergy = MIN(localEnergy / totalEnergy, 1.0);

    // We quickly attempt to reach a value that is higher than the current one.
    const double convergenceSpeedUp = 0.8;
    // We slowly decay into a value that is lower than the current one.
    const double convergenceSlowDown = 0.08;

    double convergenceSpeed = normalizedEnergy > lastEnergy ? convergenceSpeedUp : convergenceSlowDown;
    // To make sure the result is not flapping we smooth (lerp) using the previous
    // result.
    double lerpEnergy = (normalizedEnergy * convergenceSpeed) + lastEnergy * (1.0 - convergenceSpeed);
    // Gate the result for safety -- may mathematically not be needed, too lazy to
    // find out.
    double slopedEnergy = MIN(lerpEnergy, 1.0);

    lastEnergy = slopedEnergy;

    CGFloat scaleByPixel = slopedEnergy * depth;
    // double peakZoomBlurAmount = (scaleByPixel * scaleByPixel) / 2.0;

    // We want to have an enlarged image the moment the beat hits, thus we start
    // large as that is when we are being called within the phase of the rhythm.
    CGFloat scaleByFactor = 1.0 / (layer.bounds.size.width / scaleByPixel);
    CGFloat upFactor = scaleByFactor * 0.6;    // soften peak
    CGFloat downFactor = scaleByFactor * 0.1;  // shallow undershoot

    CATransform3D peakUp = CATransform3DIdentity;
    peakUp = CATransform3DTranslate(peakUp, halfSize.width, halfSize.height, 0.0);
    peakUp = CATransform3DScale(peakUp, 1.0 + upFactor, 1.0 + upFactor, 1.0);
    peakUp = CATransform3DTranslate(peakUp, -halfSize.width, -halfSize.height, 0.0);

    CATransform3D peakDown = CATransform3DIdentity;
    peakDown = CATransform3DTranslate(peakDown, halfSize.width, halfSize.height, 0.0);
    peakDown = CATransform3DScale(peakDown, 1.0 - downFactor, 1.0 - downFactor, 1.0);
    peakDown = CATransform3DTranslate(peakDown, -halfSize.width, -halfSize.height, 0.0);

    // Exactly one beat duration.
    double beatDuration = 60.0 / currentTempo;

    // Clear prior animations to avoid overlap/resonance.
    [layer removeAnimationForKey:@"beatPumping"];
    [_finalFxLayer removeAnimationForKey:@"beatWarping"];
#ifdef WITH_HELO
    [_heloLayer removeAnimationForKey:@"cornerFlashing"];
#endif

    // Gentle swing: identity -> soft peak -> shallow undershoot -> identity over
    // one beat.
    CAKeyframeAnimation* pump = [CAKeyframeAnimation animationWithKeyPath:@"transform"];
    // CAKeyframeAnimation* pump = [CAKeyframeAnimation
    // animationWithKeyPath:@"filters.CIAffineClamp.transform"];
    pump.values = @[
        [NSValue valueWithCATransform3D:CATransform3DIdentity], [NSValue valueWithCATransform3D:peakUp], [NSValue valueWithCATransform3D:peakDown],
        [NSValue valueWithCATransform3D:CATransform3DIdentity]
    ];
    pump.keyTimes = @[ @0.0, @0.35, @0.75, @1.0 ];
    pump.timingFunctions = @[
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut], [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut],
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn]
    ];
    pump.duration = beatDuration;
    pump.autoreverses = NO;

    layer.transform = CATransform3DIdentity;  // keep model neutral
    //[_clampFilter setValue:[NSValue
    //valueWithCATransform3D:CATransform3DIdentity] forKey:@"transform"];
    [layer addAnimation:pump forKey:@"beatPumping"];

    // Blur: soften in parallel, ending at 0 within one beat.
    //     CAKeyframeAnimation* blur = [CAKeyframeAnimation
    //     animationWithKeyPath:@"backgroundFilters.CIZoomBlur.inputAmount"];
    //     blur.values = @[
    //         @(peakZoomBlurAmount * 0.1),
    //         @(peakZoomBlurAmount * 0.01),
    //         @(0.0)
    //     ];
    //     blur.keyTimes = @[@0.0, @0.6, @1.0];
    //     blur.timingFunctions = @[
    //         [CAMediaTimingFunction
    //         functionWithName:kCAMediaTimingFunctionEaseInEaseOut],
    //         [CAMediaTimingFunction
    //         functionWithName:kCAMediaTimingFunctionEaseIn]
    //     ];
    //     blur.duration = beatDuration;
    //     blur.autoreverses = NO;
    //     [_finalFxLayer addAnimation:blur forKey:@"beatWarping"];

    [self animateChannelSeparationWithRed:_red green:_green blue:_blue beatEnergy:slopedEnergy currentTempo:currentTempo];

#ifdef WITH_HELO
    CAKeyframeAnimation* glow = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    // We want the lighting to be very dim for low values and to only become
    // prominent with energy levels way above 50%.
    float glowQuantum = powf(slopedEnergy, 5);
    glow.values = @[ @(glowQuantum * 0.6), @(glowQuantum * 0.3), @(0.0) ];
    glow.keyTimes = blur.keyTimes;
    glow.timingFunctions = blur.timingFunctions;
    glow.duration = beatDuration;
    glow.autoreverses = NO;
    [_heloLayer addAnimation:glow forKey:@"cornerFlashing"];
#endif
}

- (void)beatShakingLayer:(CALayer*)layer
{
    static BOOL forward = YES;
    const double phaseLength = (60.0 * (moveBeats / 2.0)) / currentTempo;
    double angleToAdd = (M_PI_2 / 180.0) * 10.0;

    forward = !forward;

    if (!forward) {
        angleToAdd = angleToAdd * -1.0;
    }

    CFTimeInterval anchorTime = CACurrentMediaTime();
    CABasicAnimation* animation = [self beatShakeRotationForAngle:angleToAdd duration:phaseLength beginTime:anchorTime];

    [layer addAnimation:animation forKey:@"beatShaking"];

    //    [self applyStaggeredChannelShakeWithAngle:angleToAdd
    //                                   phaseLength:phaseLength
    //                                     anchorTime:anchorTime];
}

- (CABasicAnimation*)beatShakeRotationForAngle:(double)angle duration:(CFTimeInterval)duration beginTime:(CFTimeInterval)beginTime
{
    CABasicAnimation* animation = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    animation.toValue = @(angle);
    animation.fromValue = @(0.0);
    animation.repeatCount = 1.0f;
    animation.autoreverses = YES;
    animation.duration = duration;
    animation.beginTime = beginTime;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    animation.fillMode = kCAFillModeBoth;
    animation.removedOnCompletion = NO;

    return animation;
}

- (void)applyStaggeredChannelShakeWithAngle:(double)angle phaseLength:(double)phaseLength anchorTime:(CFTimeInterval)anchorTime
{
    if (_red == nil || _green == nil || _blue == nil) {
        return;
    }

    // Slight offsets: red starts first, blue follows, green last. All share the
    // same speed/duration.
    const double blueDelay = phaseLength * 1.33;
    const double greenDelay = phaseLength * 0.96;

    const double redDuration = phaseLength;
    const double blueDuration = phaseLength;
    const double greenDuration = phaseLength;

    //    [_red removeAnimationForKey:@"beatShaking.red"];
    //    [_blue removeAnimationForKey:@"beatShaking.blue"];
    //    [_green removeAnimationForKey:@"beatShaking.green"];

    [_red addAnimation:[self beatShakeRotationForAngle:angle duration:redDuration beginTime:anchorTime] forKey:@"beatShaking.red"];

    [_blue addAnimation:[self beatShakeRotationForAngle:angle duration:blueDuration beginTime:anchorTime + blueDelay] forKey:@"beatShaking.blue"];

    [_green addAnimation:[self beatShakeRotationForAngle:angle duration:greenDuration beginTime:anchorTime + greenDelay] forKey:@"beatShaking.green"];
}

- (void)tempoChange:(NSNotification*)notification
{
    NSNumber* tempo = notification.object;
    float value = [tempo floatValue];
    if (value > 0.0) {
        currentTempo = value;
    }
    [self animate];
}

- (void)setStill:(BOOL)still animated:(BOOL)animated
{
    CGRect contentsBounds;
    CGRect contentsFrame;

    if (still) {
        contentsBounds = self.bounds;
        contentsFrame = self.bounds;
    } else {
        contentsBounds = CGRectMake(0.0, 0.0, self.bounds.size.width - (self.additionalSafeAreaInsets.left + self.additionalSafeAreaInsets.right),
                                    self.bounds.size.height - (self.additionalSafeAreaInsets.top + self.additionalSafeAreaInsets.bottom));
        contentsFrame =
            CGRectMake(self.additionalSafeAreaInsets.left, self.additionalSafeAreaInsets.top, contentsBounds.size.width, contentsBounds.size.height);
    }

    //_imageLayer.filters = still ? nil : @[ _bloomFilter ];

    //_imageLayer.mask = still ? nil : _maskLayer;

    //_overlayLayer.opacity = still ? 0.0 : _overlayIntensity;
    //_finalFxLayer.opacity = still ? 0.0 : 1.0;
    //_backingLayer.bounds = contentsBounds;
    //_backingLayer.frame = contentsFrame;

    CGFloat scaleByFactor = (self.bounds.size.width - (self.additionalSafeAreaInsets.left + self.additionalSafeAreaInsets.right)) / self.bounds.size.width;

    CGFloat startScale = _backingLayer.presentationLayer.transform.m11;
    CGFloat endScale = still ? 1.0 : scaleByFactor;

    CGFloat startOpacity = _overlayLayer.presentationLayer.opacity;
    CGFloat endOpacity = still ? 0.0 : _overlayIntensity;

    CGFloat startStillOpacity = _stillImageLayer.presentationLayer.opacity;
    CGFloat endStillOpacity = still ? 1.0 : 0.0;

    CGFloat startImageOpacity = _imageLayer.presentationLayer.opacity;
    CGFloat endImageOpacity = still ? 0.0 : 1.0;

    CGFloat startGlowOpacity = _glowLayer.presentationLayer.opacity;
    CGFloat endGlowOpacity = still ? 0.0 : 0.6;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    _backingLayer.transform = CATransform3DScale(CATransform3DIdentity, endScale, endScale, 1.0);
    //    _overlayLayer.opacity = endOpacity;

    _overlayLayer.opacity = endOpacity;
    _glowLayer.opacity = endOpacity;
    _stillImageLayer.opacity = endStillOpacity;
    _imageLayer.opacity = endImageOpacity;
    _imageCopyLayer.opacity = endImageOpacity;

    if (animated) {
        //        CATransform3D tr = CATransform3DIdentity;
        //        const CGSize halfSize = CGSizeMake(contentsBounds.size.width
        //        / 2.0, contentsBounds.size.height / 2.0); tr =
        //        CATransform3DTranslate(tr, halfSize.width, halfSize.height, 0.0);
        //        tr = CATransform3DScale(tr, 1.0 + scaleByFactor, 1.0 +
        //        scaleByFactor, 1.0); tr = CATransform3DTranslate(tr,
        //        -halfSize.width, -halfSize.height, 0.0);
        CAAnimation* scale = nil;
        CAAnimation* fadeOverlay = nil;
        CAAnimation* fadeStill = nil;
        CAAnimation* fadeImage = nil;
        CAAnimation* fadeGlow = nil;

        if (still) {
            CABasicAnimation* s = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
            s.removedOnCompletion = NO;
            s.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
            s.fromValue = @(startScale);
            s.toValue = @(endScale);
            s.duration = 0.2;
            scale = s;

            CABasicAnimation* f = [CABasicAnimation animationWithKeyPath:@"opacity"];
            f.removedOnCompletion = NO;
            f.fillMode = kCAFillModeForwards;
            f.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            f.fromValue = @(startOpacity);
            f.toValue = @(endOpacity);
            f.duration = 0.5;
            fadeOverlay = f;

            f = [CABasicAnimation animationWithKeyPath:@"opacity"];
            f.removedOnCompletion = NO;
            f.fillMode = kCAFillModeForwards;
            f.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
            f.fromValue = @(startStillOpacity);
            f.toValue = @(endStillOpacity);
            f.duration = 0.3;
            fadeStill = f;

            f = [CABasicAnimation animationWithKeyPath:@"opacity"];
            f.removedOnCompletion = NO;
            f.fillMode = kCAFillModeForwards;
            f.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
            f.fromValue = @(startImageOpacity);
            f.toValue = @(endImageOpacity);
            f.duration = 0.7;
            fadeImage = f;

            f = [CABasicAnimation animationWithKeyPath:@"opacity"];
            f.removedOnCompletion = NO;
            f.fillMode = kCAFillModeForwards;
            f.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
            f.fromValue = @(startGlowOpacity);
            f.toValue = @(endGlowOpacity);
            f.duration = 0.3;
            fadeGlow = f;
        } else {
            CASpringAnimation* s = [CASpringAnimation animationWithKeyPath:@"transform.scale"];
            s.removedOnCompletion = NO;
            s.fromValue = @(startScale);
            s.toValue = @(endScale);
            s.damping = 30.0;  // lower = bouncier
            s.stiffness = 1000.0;
            s.mass = 2.0;
            s.initialVelocity = 5.0;          // positive to overshoot
            s.duration = s.settlingDuration;  // auto-computed
            scale = s;

            CABasicAnimation* f = [CABasicAnimation animationWithKeyPath:@"opacity"];
            f.removedOnCompletion = NO;
            f.fillMode = kCAFillModeForwards;
            f.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
            f.fromValue = @(startOpacity);
            f.toValue = @(endOpacity);
            f.duration = 0.5;
            fadeOverlay = f;

            f = [CABasicAnimation animationWithKeyPath:@"opacity"];
            f.removedOnCompletion = NO;
            f.fillMode = kCAFillModeForwards;
            f.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
            f.fromValue = @(startStillOpacity);
            f.toValue = @(endStillOpacity);
            f.duration = 0.5;
            fadeStill = f;

            f = [CABasicAnimation animationWithKeyPath:@"opacity"];
            f.removedOnCompletion = NO;
            f.fillMode = kCAFillModeForwards;
            f.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
            f.fromValue = @(startImageOpacity);
            f.toValue = @(endImageOpacity);
            f.duration = 0.1;
            fadeImage = f;

            f = [CABasicAnimation animationWithKeyPath:@"opacity"];
            f.removedOnCompletion = NO;
            f.fillMode = kCAFillModeForwards;
            f.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
            f.fromValue = @(startGlowOpacity);
            f.toValue = @(endGlowOpacity);
            f.duration = 1.0;
            fadeGlow = f;
        }
        // Overlay and glow should animate similarly as they are "one" thing.
        [_overlayLayer addAnimation:fadeOverlay forKey:@"fade"];
        [_glowLayer addAnimation:fadeGlow forKey:@"fade"];

        [_imageLayer addAnimation:fadeImage forKey:@"fade"];
        [_imageCopyLayer addAnimation:fadeImage forKey:@"fade"];
        [_stillImageLayer addAnimation:fadeStill forKey:@"fade"];
        [_backingLayer addAnimation:scale forKey:@"boundsFlonk"];
    }
    [CATransaction commit];
}

- (void)beatEffect:(NSNotification*)notification
{
    //    return;
    const NSDictionary* dict = notification.object;

    NSNumber* tempo = dict[kBeatNotificationKeyTempo];
    float value = [tempo floatValue];
    if (value > 0.0) {
        if (value != currentTempo) {
            currentTempo = value;
            [self animate];
        }
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    // Bomb the bass!
    [self beatPumpingLayer:self.layer
               localEnergy:[dict[kBeatNotificationKeyLocalEnergy] doubleValue]
               totalEnergy:[dict[kBeatNotificationKeyTotalEnergy] doubleValue]];

    const unsigned long long beatIndex = [dict[kBeatNotificationKeyBeat] unsignedLongLongValue];

    double localEnergy = [dict[kBeatNotificationKeyLocalEnergy] doubleValue];
    double totalEnergy = [dict[kBeatNotificationKeyTotalEnergy] doubleValue];

    // Attempt to get a reasonably wide signal range by normalizing the locals
    // peaks by the globally most energy loaded samples.
    const double normalizedEnergy = MIN(localEnergy / totalEnergy, 1.0);

    // We quickly attempt to reach a value that is higher than the current one.
    const double convergenceSpeedUp = 0.8;
    // We slowly decay into a value that is lower than the current one.
    const double convergenceSlowDown = 0.08;

    double convergenceSpeed = normalizedEnergy > lastEnergy ? convergenceSpeedUp : convergenceSlowDown;
    // To make sure the result is not flapping we smooth (lerp) using the previous
    // result.
    double lerpEnergy = (normalizedEnergy * convergenceSpeed) + lastEnergy * (1.0 - convergenceSpeed);
    // Gate the result for safety -- may mathematically not be needed, too lazy to
    // find out.
    double slopedEnergy = MIN(lerpEnergy, 1.0);

    if (slopedEnergy < 0.5) {
        moveBeats = 4;
    } else if (beatIndex % 16 == 1) {
        moveBeats = 1 + ((moveBeats + 1) % 4);
    }
    // We start shaking only on the first beat of a bar.
    if (beatIndex % 4 == 1) {
        [self beatShakingLayer:_backingLayer];
    }

    [CATransaction commit];
}

- (CGFloat)randInRange:(CGFloat)r
{
    return ((CGFloat) arc4random_uniform((uint32_t) (2 * r)) - r);
}

- (void)animateLayer:(CALayer*)layer radius:(CGFloat)r
{
    // Current position (presentation if animating)
    CALayer* pres = layer;
    CGPoint from = pres.position;

    // New target nearby
    CGPoint to = CGPointMake(from.x + [self randInRange:r], from.y + [self randInRange:r]);

    CFTimeInterval dur = 0.1 + (arc4random_uniform(500) / 1000.0);  // 3–5s

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    layer.position = to;  // commit end position
    [CATransaction setCompletionBlock:^{
        [self animateLayer:layer radius:r];  // chain to next step
    }];

    CABasicAnimation* anim = [CABasicAnimation animationWithKeyPath:@"position"];
    anim.fromValue = [NSValue valueWithPoint:from];
    anim.toValue = [NSValue valueWithPoint:to];
    anim.duration = dur;
    anim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];

    [layer addAnimation:anim forKey:@"wander"];
    [CATransaction commit];
}

- (void)animateChannelSeparationWithRed:(CALayer*)red
                                  green:(CALayer*)green
                                   blue:(CALayer*)blue
                             beatEnergy:(double)slopedEnergy
                           currentTempo:(double)currentTempo
{
    double beatDuration = 60.0 / currentTempo;
    CGFloat maxRadius = 11.0f * (slopedEnergy * slopedEnergy);
    CGFloat blend = 0.2f;

    // Current visual offsets BEFORE removing animations
    NSPoint (^currentTranslation)(CALayer*) = ^NSPoint(CALayer* l) {
        CALayer* pres = l.presentationLayer ?: l;
        CATransform3D t = pres.transform;
        return NSMakePoint(t.m41, t.m42);
    };
    NSPoint rFrom = currentTranslation(red);
    NSPoint gFrom = currentTranslation(green);
    NSPoint bFrom = currentTranslation(blue);

    // Commit current translation to model to avoid snapping
    red.transform = CATransform3DMakeTranslation(rFrom.x, rFrom.y, 0.0);
    green.transform = CATransform3DMakeTranslation(gFrom.x, gFrom.y, 0.0);
    blue.transform = CATransform3DMakeTranslation(bFrom.x, bFrom.y, 0.0);

    [red removeAnimationForKey:@"channelShift"];
    [green removeAnimationForKey:@"channelShift"];
    [blue removeAnimationForKey:@"channelShift"];

    // New target exactly on the current radius (energy-scaled), lightly blended
    // with previous.
    NSPoint (^randomTarget)(void) = ^NSPoint {
        CGFloat a = (CGFloat) arc4random_uniform(1000) / 1000.0f * 2.0f * (CGFloat) M_PI;
        return NSMakePoint(cos(a) * maxRadius, sin(a) * maxRadius);
    };
    NSPoint target = randomTarget();
    NSPoint rNext = NSMakePoint(_rCurrent.x * (1.0f - blend) + target.x * blend, _rCurrent.y * (1.0f - blend) + target.y * blend);
    target = randomTarget();
    NSPoint gNext = NSMakePoint(_gCurrent.x * (1.0f - blend) + target.x * blend, _gCurrent.y * (1.0f - blend) + target.y * blend);
    target = randomTarget();
    NSPoint bNext = NSMakePoint(_bCurrent.x * (1.0f - blend) + target.x * blend, _bCurrent.y * (1.0f - blend) + target.y * blend);

    CAKeyframeAnimation* (^shift)(NSPoint, NSPoint) = ^CAKeyframeAnimation*(NSPoint from, NSPoint to) {
        CAKeyframeAnimation* a = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation"];
        a.values = @[
            [NSValue valueWithPoint:from],         // max at beat
            [NSValue valueWithPoint:NSZeroPoint],  // origin mid-beat
            [NSValue valueWithPoint:to]            // drift to next peak
        ];
        // Keep maximum separation on-beat (0 and 1); return to center shortly
        // before the next beat.
        a.keyTimes = @[ @0.0, @0.8, @1.0 ];
        a.timingFunctions = @[
            [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut],
            [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]
        ];
        a.duration = beatDuration;
        a.autoreverses = NO;
        return a;
    };

    [red addAnimation:shift(rFrom, rNext) forKey:@"channelShift"];
    [green addAnimation:shift(gFrom, gNext) forKey:@"channelShift"];
    [blue addAnimation:shift(bFrom, bNext) forKey:@"channelShift"];

    // Set model to the next peak for the next beat
    red.transform = CATransform3DMakeTranslation(rNext.x, rNext.y, 0.0);
    green.transform = CATransform3DMakeTranslation(gNext.x, gNext.y, 0.0);
    blue.transform = CATransform3DMakeTranslation(bNext.x, bNext.y, 0.0);

    _rCurrent = rNext;
    _gCurrent = gNext;
    _bCurrent = bNext;
}

- (CALayer*)colorSeparationLayerForImage:(NSImage*)image frame:(CGRect)frame
{
    CALayer* container = [CALayer layer];
    container.frame = frame;
    // container.contents = image;
    container.masksToBounds = YES;
    container.magnificationFilter = kCAFilterLinear;
    container.minificationFilter = kCAFilterLinear;
    container.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    container.allowsEdgeAntialiasing = YES;
    container.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    container.drawsAsynchronously = YES;

    // Helper to make a channel layer
    CALayer* (^channel)(CGFloat r, CGFloat g, CGFloat b) = ^CALayer*(CGFloat r, CGFloat g, CGFloat b) {
        CALayer* layer = [CALayer layer];

        layer.magnificationFilter = kCAFilterLinear;
        layer.minificationFilter = kCAFilterLinear;
        layer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
        layer.allowsEdgeAntialiasing = YES;
        layer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
        layer.drawsAsynchronously = YES;
        layer.masksToBounds = NO;
        layer.contentsGravity = kCAGravityCenter;

        layer.frame = container.bounds;
        // double maxRadius = 20.0;
        // layer.frame = CGRectInset(container.bounds, -maxRadius, -maxRadius);
        // layer.bounds = CGRectMake(0, 0, container.bounds.size.width,
        // container.bounds.size.height); // keep content size layer.position =
        // CGPointMake(CGRectGetMidX(container.bounds),
        // CGRectGetMidY(container.bounds));

        CIFilter* cm = [CIFilter filterWithName:@"CIColorMatrix"];
        // Keep only one channel, zero the others
        [cm setValue:[CIVector vectorWithX:r Y:0 Z:0 W:0] forKey:@"inputRVector"];
        [cm setValue:[CIVector vectorWithX:0 Y:g Z:0 W:0] forKey:@"inputGVector"];
        [cm setValue:[CIVector vectorWithX:0 Y:0 Z:b W:0] forKey:@"inputBVector"];
        [cm setValue:[CIVector vectorWithX:0 Y:0 Z:0 W:1] forKey:@"inputAVector"];

        layer.filters = @[ cm ];
        layer.opacity = 0.7;
        layer.compositingFilter = [CIFilter filterWithName:@"CIAdditionCompositing"];

        return layer;
    };

    _red = channel(1, 0, 0);
    _green = channel(0, 1, 0);
    _blue = channel(0, 0, 1);

    [container addSublayer:_blue];
    [container addSublayer:_green];
    [container addSublayer:_red];

    return container;
}

- (CALayer*)makeBackingLayer
{
    CALayer* layer = [CALayer layer];
    layer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    layer.frame = self.bounds;
    layer.masksToBounds = NO;
    layer.drawsAsynchronously = YES;
    layer.anchorPoint = CGPointMake(0.5, 0.5);

    CGPoint center = NSMakePoint(CGRectGetMidX(layer.bounds), CGRectGetMidY(layer.bounds));

    // CGRect contentsBounds = CGRectMake(0.0, 0.0, self.bounds.size.width -
    // (self.additionalSafeAreaInsets.left + self.additionalSafeAreaInsets.right),
    // self.bounds.size.height - (self.additionalSafeAreaInsets.top +
    // self.additionalSafeAreaInsets.bottom)); CGRect contentsFrame =
    // CGRectMake(self.additionalSafeAreaInsets.left,
    // self.additionalSafeAreaInsets.top, self.bounds.size.width -
    // (self.additionalSafeAreaInsets.left + self.additionalSafeAreaInsets.right),
    // self.bounds.size.height - (self.additionalSafeAreaInsets.top +
    // self.additionalSafeAreaInsets.bottom)); CGRect contentsFrame =
    // CGRectInset(self.bounds, self.additionalSafeAreaInsets.left,
    // self.additionalSafeAreaInsets.top);

    _bloomFilter = [CIFilter filterWithName:@"CIBloom"];
    [_bloomFilter setDefaults];
    [_bloomFilter setValue:[NSNumber numberWithFloat:21.0] forKey:@"inputRadius"];
    [_bloomFilter setValue:[NSNumber numberWithFloat:1.5] forKey:@"inputIntensity"];

    //    CIFilter* linesFilter = [CIFilter filterWithName:@"CIHatchedScreen"];
    //    [linesFilter setDefaults];
    //    [linesFilter setValue: [NSNumber numberWithFloat:4.0] forKey:
    //    @"inputWidth"]; [linesFilter setValue: [NSNumber numberWithFloat:0.0]
    //    forKey: @"inputAngle"]; [linesFilter setValue: [NSNumber
    //    numberWithFloat:0.02] forKey: @"inputSharpness"];
    CIFilter* linesFilter = [CIFilter filterWithName:@"CICircularScreen"];
    [linesFilter setDefaults];
    [linesFilter setValue:[NSNumber numberWithFloat:5.0] forKey:@"inputWidth"];
    [linesFilter setValue:[NSNumber numberWithFloat:0.01] forKey:@"inputSharpness"];
    [linesFilter setValue:[CIVector vectorWithCGPoint:center] forKey:@"inputCenter"];

    CIFilter* darkenFilter = [CIFilter filterWithName:@"CIColorControls"];
    [darkenFilter setDefaults];
    [darkenFilter setValue:[NSNumber numberWithFloat:-0.46] forKey:@"inputBrightness"];
    [darkenFilter setValue:[NSNumber numberWithFloat:0.02] forKey:@"inputContrast"];

    CIFilter* lightenFilter = [CIFilter filterWithName:@"CIGammaAdjust"];
    [lightenFilter setDefaults];
    [lightenFilter setValue:[NSNumber numberWithFloat:0.05] forKey:@"inputPower"];

    //    hexagonalPixelateFilter.scale = 50
    //
    CIFilter* additionFilter = [CIFilter filterWithName:@"CIAdditionCompositing"];
    [additionFilter setDefaults];

    if ((_style & CoverViewStyleGlowBehindCoverAtLaser) == CoverViewStyleGlowBehindCoverAtLaser) {
#ifdef WITH_HELO
        _heloLayer = [CALayer layer];
        _heloLayer.magnificationFilter = kCAFilterLinear;
        _heloLayer.minificationFilter = kCAFilterLinear;
        _heloLayer.contents = [NSImage resizedImage:[NSImage imageNamed:@"HeloGlow"] size:contentsBounds.size];

        //_glowLayer.contents = [self lightTunnelFilterImage:[input CG]
        //withInputCenter:CGPointMake(self.bounds.size.width / 2.0,
        //self.bounds.size.height / 2.0) inputRotation:0.0 inputRadius:0.0];
        _heloLayer.frame = CGRectInset(contentsFrame, -55.0, -55.0);
        //    _glowLayer.frame = CGRectOffset(_glowLayer.frame, -50.0, -50.0);
        _heloLayer.allowsEdgeAntialiasing = YES;
        _heloLayer.shouldRasterize = YES;
        _heloLayer.opacity = 0.0f;
        _heloLayer.filters = @[ bloomFilter ];
        _heloLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
        _heloLayer.rasterizationScale = layer.contentsScale;
        _heloLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
        _heloLayer.masksToBounds = YES;
        _heloLayer.compositingFilter = additionFilter;
        [layer addSublayer:_heloLayer];
#endif
        _glowLayer = [CALayer layer];
        _glowLayer.magnificationFilter = kCAFilterLinear;
        _glowLayer.minificationFilter = kCAFilterLinear;
        _glowLayer.contents = [NSImage resizedImage:[NSImage imageNamed:@"FadeGlow"] size:self.bounds.size];

        //_glowLayer.contents = [self lightTunnelFilterImage:[input CG]
        //withInputCenter:CGPointMake(self.bounds.size.width / 2.0,
        //self.bounds.size.height / 2.0) inputRotation:0.0 inputRadius:0.0];
        _glowLayer.frame = CGRectInset(self.bounds, -100.0, -100.0);
        //    _glowLayer.frame = CGRectOffset(_glowLayer.frame, -50.0, -50.0);
        _glowLayer.allowsEdgeAntialiasing = YES;
        _glowLayer.shouldRasterize = YES;
        _glowLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
        _glowLayer.rasterizationScale = layer.contentsScale;
        _glowLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
        _glowLayer.backgroundFilters = @[ _bloomFilter ];
        _glowLayer.masksToBounds = YES;
        _glowLayer.drawsAsynchronously = YES;
        _glowLayer.filters = @[ _bloomFilter ];
        _glowLayer.compositingFilter = additionFilter;
        [layer addSublayer:_glowLayer];
    }

    // A layer meant to assert that our cover pops out and has maximal contrast.
    // We need this because <FIXME: Why?>
    _backingLayer = [CALayer layer];
    _backingLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    _backingLayer.frame = self.bounds;
    //_backingLayer.shouldRasterize = YES;
    _backingLayer.masksToBounds = NO;
    _backingLayer.drawsAsynchronously = YES;
    _backingLayer.cornerRadius = 7.0f;
    _backingLayer.anchorPoint = CGPointMake(0.5, 0.5);
    _backingLayer.allowsEdgeAntialiasing = YES;
    _backingLayer.magnificationFilter = kCAFilterLinear;
    _backingLayer.minificationFilter = kCAFilterLinear;
    _backingLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    //_backingLayer.backgroundColor = [NSColor controlBackgroundColor].CGColor;
    _backingLayer.backgroundColor = [NSColor clearColor].CGColor;

    _maskLayer = [CALayer layer];
    _maskLayer.contents = [NSImage imageNamed:@"FadeMask"];
    _maskLayer.frame = CGRectMake(-self.bounds.size.width / 2, -self.bounds.size.height / 2, self.bounds.size.width * 2, self.bounds.size.height * 2);
    _maskLayer.autoresizingMask = kCALayerNotSizable;
    _maskLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    _maskLayer.allowsEdgeAntialiasing = YES;
    _maskLayer.magnificationFilter = kCAFilterLinear;
    _maskLayer.minificationFilter = kCAFilterLinear;
    _maskLayer.position = CGPointMake(self.bounds.size.width / 2, self.bounds.size.height / 2);

    //_imageCopyLayer = [self colorSeparationLayerForImage:[NSImage
    //resizedImageWithData:[MediaMetaData defaultArtworkData]
    //size:self.bounds.size] frame:self.bounds];

    _imageCopyLayer = [CALayer layer];
    _imageCopyLayer.magnificationFilter = kCAFilterLinear;
    _imageCopyLayer.minificationFilter = kCAFilterLinear;
    _imageCopyLayer.frame = self.bounds;
    _imageCopyLayer.contents = [NSImage resizedImageWithData:[MediaMetaData defaultArtworkData] size:self.bounds.size];
    _imageCopyLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    //_imageCopyLayer.cornerRadius = 7.0f;
    _imageCopyLayer.allowsEdgeAntialiasing = YES;
    _imageCopyLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    _imageCopyLayer.drawsAsynchronously = YES;
    _imageCopyLayer.masksToBounds = YES;
    if ((_style & CoverViewStyleGlowBehindCoverAtLaser) == CoverViewStyleGlowBehindCoverAtLaser) {
        _imageCopyLayer.borderWidth = 1.0;
        //_imageLayer.borderColor = [NSColor windowFrameColor].CGColor;
        _imageCopyLayer.borderColor = [[Defaults sharedDefaults] regularBeamColor].CGColor;
    }

    if ((_style & CoverViewStyleSepiaForSecondImageLayer) == CoverViewStyleSepiaForSecondImageLayer) {
        _imageCopyLayer.filters = @[ darkenFilter ];
    }
    //    _imageCopyLayer.opacity = _secondImageLayerOpacity;
    [_backingLayer addSublayer:_imageCopyLayer];

    _imageLayer = [self colorSeparationLayerForImage:[NSImage resizedImageWithData:[MediaMetaData defaultArtworkData] size:self.bounds.size] frame:self.bounds];
    _imageLayer.frame = self.bounds;
    _imageLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    _imageLayer.rasterizationScale = layer.contentsScale;
    _imageLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    //_imageLayer.cornerRadius = 7.0f;
    _imageLayer.frame = self.bounds;
    if ((_style & CoverViewStyleGlowBehindCoverAtLaser) == CoverViewStyleGlowBehindCoverAtLaser) {
        _imageLayer.borderWidth = 1.0;
        //_imageLayer.borderColor = [NSColor windowFrameColor].CGColor;
        _imageLayer.borderColor = [[[Defaults sharedDefaults] lightBeamColor] colorWithAlphaComponent:0.3].CGColor;
    }
    CIFilter* fxFilter = [CIFilter filterWithName:@"CIZoomBlur"];
    [fxFilter setDefaults];
    [fxFilter setValue:[NSNumber numberWithFloat:0.0] forKey:@"inputAmount"];

    //    if ((_style & CoverViewStyleRotatingLaser) ==
    //    CoverViewStyleRotatingLaser) {
    //        _imageLayer.filters = @[ _bloomFilter ];
    //    }

    [_backingLayer addSublayer:_imageLayer];

    if ((_style & CoverViewStyleRotatingLaser) == CoverViewStyleRotatingLaser) {
        _rotateLayer = [CALayer layer];
        _rotateLayer.autoresizingMask = kCALayerNotSizable;
        //_rotateLayer.anchorPoint = CGPointMake(0.5, 0.507);
        _rotateLayer.drawsAsynchronously = YES;
        _rotateLayer.position = CGPointMake(ceil(_backingLayer.bounds.size.width / 2.0), ceil(_backingLayer.bounds.size.height / 2.0));
        _rotateLayer.bounds = _maskLayer.bounds;
        _rotateLayer.compositingFilter = additionFilter;
        [_imageLayer addSublayer:_rotateLayer];

        _overlayLayer = [CALayer layer];
        _overlayLayer.contents = [NSImage imageNamed:kLayerImageName];
        _overlayLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
        _overlayLayer.shouldRasterize = YES;
        _overlayLayer.cornerRadius = 7.0f;
        _rotateLayer.compositingFilter = additionFilter;
        _overlayLayer.allowsEdgeAntialiasing = YES;
        _overlayLayer.drawsAsynchronously = YES;
        _overlayLayer.rasterizationScale = layer.contentsScale;
        _overlayLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
        _overlayLayer.magnificationFilter = kCAFilterLinear;
        _overlayLayer.minificationFilter = kCAFilterLinear;
        _overlayLayer.opacity = _overlayIntensity;
        _overlayLayer.frame = _maskLayer.bounds;
        [_rotateLayer addSublayer:_overlayLayer];
    }

#ifndef HIDE_COVER_DEBBUG
    [layer addSublayer:_backingLayer];
#endif

    _finalFxLayer = [CALayer layer];
    _finalFxLayer.frame = self.bounds;
    _finalFxLayer.backgroundFilters = @[ fxFilter ];
    _finalFxLayer.drawsAsynchronously = YES;
    [_backingLayer addSublayer:_finalFxLayer];

    _stillImageLayer = [CALayer layer];
    _stillImageLayer.magnificationFilter = kCAFilterLinear;
    _stillImageLayer.minificationFilter = kCAFilterLinear;
    _stillImageLayer.frame = self.bounds;
    _stillImageLayer.contents = [NSImage resizedImageWithData:[MediaMetaData defaultArtworkData] size:self.bounds.size];
    _stillImageLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    _stillImageLayer.allowsEdgeAntialiasing = YES;
    _stillImageLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    _stillImageLayer.drawsAsynchronously = YES;
    _stillImageLayer.masksToBounds = YES;
    [_backingLayer addSublayer:_stillImageLayer];

    return layer;
}

- (void)setImage:(NSImage*)image
{
    [self setImage:image animated:YES];
}

// Fade from current background color to the given one.
- (void)animateLayer:(CALayer*)layer toBackgroundColor:(NSColor*)color
{
    CABasicAnimation* animation = [CABasicAnimation animationWithKeyPath:@"backgroundColor"];
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    animation.fillMode = kCAFillModeForwards;
    animation.removedOnCompletion = NO;
    animation.fromValue = (id) layer.presentationLayer.backgroundColor;
    animation.toValue = (id) color.CGColor;
    animation.repeatCount = 1.0f;
    animation.autoreverses = NO;
    animation.duration = 4.0f;
    [layer addAnimation:animation forKey:@"BackgroundColorTransition"];
}

- (void)setImage:(NSImage* _Nullable)image animated:(BOOL)animated
{
    NSColor* averageColor = nil;
    if (image == nil) {
        unknown = YES;
        image = [NSImage resizedImageWithData:[MediaMetaData defaultArtworkData] size:self.bounds.size];
        averageColor = [NSColor windowBackgroundColor];
    } else {
        unknown = NO;
        averageColor = [image averageColor];
    }

    CGFloat travel = 100.0f;  // match your maxRadius
    CIImage* ci = [[CIImage alloc] initWithData:image.TIFFRepresentation];
    CIImage* clamped = [ci imageByClampingToExtent];
    CIContext* ctx = [CIContext contextWithOptions:nil];

    CGRect padRect = CGRectInset(ci.extent, -travel, -travel);
    CGImageRef cg = [ctx createCGImage:clamped fromRect:padRect];

    if (animated) {
        [self animateLayer:self.layer toBackgroundColor:averageColor];

        [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
            [context setDuration:2.1f];
            [context setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn]];

            self.animator.imageCopyLayer.contents = image;
            self.animator.stillImageLayer.contents = image;
            self.animator.red.contents = (__bridge id) cg;
            self.animator.green.contents = (__bridge id) cg;
            self.animator.blue.contents = (__bridge id) cg;
        }];
    } else {
        [self.layer removeAllAnimations];

        self.imageCopyLayer.contents = image;
        self.stillImageLayer.contents = image;
        self.red.contents = (__bridge id) cg;
        self.green.contents = (__bridge id) cg;
        self.blue.contents = (__bridge id) cg;
    }

    CGImageRelease(cg);
    self.layer.backgroundColor = averageColor.CGColor;
}

- (void)animate
{
    if ((_style & (CoverViewStyleRotatingLaser | CoverViewStyleGlowBehindCoverAtLaser)) == 0) {
        return;
    }

    const float beatsPerCycle = 4.0f;

    CABasicAnimation* animation = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    animation.fillMode = kCAFillModeForwards;
    animation.removedOnCompletion = NO;
    NSAssert(currentTempo > 0.0, @"current tempo set to zero, that should never happen");
    animation.duration = beatsPerCycle * 60.0f / self->currentTempo;
    const CGFloat anglePerBeat = M_PI_2 * beatsPerCycle;
    const CGFloat angleToAdd = -anglePerBeat;

    // const CGFloat scaleX = hypot(_rotateLayer.presentationLayer.transform.m11,
    // _rotateLayer.presentationLayer.transform.m12); const CGFloat angleStart =
    // atan2(_rotateLayer.presentationLayer.transform.m12 / scaleX,
    // _rotateLayer.presentationLayer.transform.m11 / scaleX);

    //    if ((_style & CoverViewStyleRotatingLaser) ==
    //    CoverViewStyleRotatingLaser) {
    //        [_rotateLayer setValue:@(anglePerBeat)
    //        forKeyPath:@"transform.rotation.z"];
    //        [_maskLayer setValue:@(anglePerBeat)
    //        forKeyPath:@"transform.rotation.z"];
    //    }
    //    if ((_style & CoverViewStyleGlowBehindCoverAtLaser) ==
    //    CoverViewStyleGlowBehindCoverAtLaser) {
    //        [_glowLayer setValue:@(anglePerBeat)
    //        forKeyPath:@"transform.rotation.z"];
    //    }

    // animation.toValue = @(0.0);
    animation.byValue = @(angleToAdd);
    animation.repeatCount = FLT_MAX;

    if ((_style & CoverViewStyleRotatingLaser) == CoverViewStyleRotatingLaser) {
        [_rotateLayer addAnimation:animation forKey:@"rotation"];
        [_maskLayer addAnimation:animation forKey:@"rotation"];
    }
    if ((_style & CoverViewStyleGlowBehindCoverAtLaser) == CoverViewStyleGlowBehindCoverAtLaser) {
        [_glowLayer addAnimation:animation forKey:@"rotation"];
    }
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

    if ((_style & CoverViewStyleRotatingLaser) == CoverViewStyleRotatingLaser) {
        _imageCopyLayer.mask = _maskLayer;
        _imageLayer.mask = _maskLayer;
    } else {
        _imageCopyLayer.mask = nil;
        _imageLayer.mask = nil;
    }

    [self animate];

    NSLog(@"we should be animating coverview");
    animating = YES;
}

- (void)stopAnimating
{
    paused = NO;
    if ((_style & CoverViewStyleRotatingLaser) == CoverViewStyleRotatingLaser) {
        //[_maskLayer removeAllAnimations];
        [_overlayLayer removeAllAnimations];
    }
    if ((_style & CoverViewStyleGlowBehindCoverAtLaser) == CoverViewStyleGlowBehindCoverAtLaser) {
        //[_glowLayer removeAllAnimations];
    }
    animating = NO;
}

- (void)startLaserRotation
{
    if ((_style & (CoverViewStyleRotatingLaser | CoverViewStyleGlowBehindCoverAtLaser)) == 0) {
        return;
    }

    const float beatsPerCycle = 4.0f;

    CABasicAnimation* animation = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    animation.fillMode = kCAFillModeForwards;
    animation.removedOnCompletion = NO;
    NSAssert(currentTempo > 0.0, @"current tempo set to zero, that should never happen");
    animation.duration = beatsPerCycle * 60.0f / self->currentTempo;
    const CGFloat anglePerBeat = M_PI_2 * beatsPerCycle;
    const CGFloat angleToAdd = -anglePerBeat;

    // const CGFloat scaleX = hypot(_rotateLayer.presentationLayer.transform.m11,
    // _rotateLayer.presentationLayer.transform.m12); const CGFloat angleStart =
    // atan2(_rotateLayer.presentationLayer.transform.m12 / scaleX,
    // _rotateLayer.presentationLayer.transform.m11 / scaleX);

    //    if ((_style & CoverViewStyleRotatingLaser) ==
    //    CoverViewStyleRotatingLaser) {
    //        [_rotateLayer setValue:@(anglePerBeat)
    //        forKeyPath:@"transform.rotation.z"];
    //        [_maskLayer setValue:@(anglePerBeat)
    //        forKeyPath:@"transform.rotation.z"];
    //    }
    //    if ((_style & CoverViewStyleGlowBehindCoverAtLaser) ==
    //    CoverViewStyleGlowBehindCoverAtLaser) {
    //        [_glowLayer setValue:@(anglePerBeat)
    //        forKeyPath:@"transform.rotation.z"];
    //    }

    // animation.toValue = @(0.0);
    animation.byValue = @(angleToAdd);
    animation.repeatCount = FLT_MAX;

    if ((_style & CoverViewStyleRotatingLaser) == CoverViewStyleRotatingLaser) {
        [_rotateLayer addAnimation:animation forKey:@"rotation"];
        [_maskLayer addAnimation:animation forKey:@"rotation"];
    }
    if ((_style & CoverViewStyleGlowBehindCoverAtLaser) == CoverViewStyleGlowBehindCoverAtLaser) {
        [_glowLayer addAnimation:animation forKey:@"rotation"];
    }
}

- (void)haltLaserRotation
{
    if ((_style & CoverViewStyleRotatingLaser) == CoverViewStyleRotatingLaser) {
        _rotateLayer.transform = _rotateLayer.presentationLayer.transform;
        [_rotateLayer removeAnimationForKey:@"rotation"];
        _maskLayer.transform = _maskLayer.presentationLayer.transform;
        [_maskLayer removeAnimationForKey:@"rotation"];
    }
    if ((_style & CoverViewStyleGlowBehindCoverAtLaser) == CoverViewStyleGlowBehindCoverAtLaser) {
        _glowLayer.transform = _glowLayer.presentationLayer.transform;
        [_glowLayer removeAnimationForKey:@"rotation"];
    }
}

- (void)resumeAnimating
{
    if (!animating || paused == NO) {
        return;
    }

    [self startLaserRotation];

    paused = NO;
}

- (void)pauseAnimating
{
    if (!animating || paused == YES) {
        return;
    }

    [self haltLaserRotation];

    paused = YES;
}

@end
