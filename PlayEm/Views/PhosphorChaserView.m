//
//  PhosphorChaserView.m
//  PlayEm
//
//  Retro phosphor spinner with CI accumulator smear (no Metal).
//
//  Created by Till Toenshoff on 08.06.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import "PhosphorChaserView.h"
#import <QuartzCore/QuartzCore.h>
#import <CoreImage/CoreImage.h>
#import <AppKit/AppKit.h>
#import "Defaults.h"

@interface PhosphorChaserView ()
@property (nonatomic, strong) CIContext *ciContext;
@property (nonatomic, strong) CIImageAccumulator *accumulator;
@property (nonatomic, strong) NSTimer *displayTimer;
@property (nonatomic) CFAbsoluteTime lastTick;
@property (nonatomic) CGFloat angle;
@property (nonatomic) CGFloat decayFactor;
@property (nonatomic) BOOL animating;
@property (nonatomic) BOOL stopping;
@property (nonatomic) BOOL disappearing;
@property (nonatomic) CFAbsoluteTime stopStart;
@property (nonatomic) NSTimeInterval stopDuration;
@property (nonatomic) NSTimeInterval disappearDuration;
@property (nonatomic) NSTimeInterval fadeOutDuration;
@property (nonatomic) NSUInteger stopGeneration;
@property (nonatomic) CFAbsoluteTime startTime;
@property (nonatomic) NSTimeInterval startRampDuration;
@property (nonatomic) NSTimeInterval radiusRampDuration;
@property (nonatomic) CFAbsoluteTime disappearStart;
@property (nonatomic) BOOL disappearComplete;
@end

@implementation PhosphorChaserView

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.masksToBounds = NO; // allow glow to spill outside bounds
        self.layer.contentsGravity = kCAGravityCenter; // avoid aspect scaling that distorts the ring
        CGFloat scale = [NSScreen mainScreen] ? [NSScreen mainScreen].backingScaleFactor : 2.0;
        self.layer.contentsScale = scale;
        self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawDuringViewResize;
        self.hidden = YES;
        self.alphaValue = 0.0;
        self.accessibilityLabel = @"Background activity indicator";

        _period = 1.0;
        _decayFactor = 0.93;        // how much of the tail persists each frame
        _stopping = NO;
        _disappearing = NO;
        
        _stopDuration = 2.0;
        _fadeOutDuration = 0.3;
        _stopGeneration = 0;
        _disappearDuration = 0.7;
        _startRampDuration = 0.7;
        _radiusRampDuration = 0.7;
        _disappearStart = 0;
        _disappearComplete = NO;
    }
    return self;
}

- (BOOL)isFlipped
{
    return YES;
}

- (void)layout
{
    [super layout];
    [self rebuildAccumulatorIfNeeded];
}

- (void)rebuildAccumulatorIfNeeded
{
    CGRect b = self.bounds;
    if (b.size.width <= 0 || b.size.height <= 0) return;
    if (!_ciContext) {
        _ciContext = [CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer: @NO}];
    }
    CGRect extent = b;
    if (!_accumulator || !CGRectEqualToRect(_accumulator.extent, extent)) {
        _accumulator = [CIImageAccumulator imageAccumulatorWithExtent:extent format:kCIFormatARGB8];
        [_accumulator setImage:[CIImage imageWithColor:[[CIColor alloc] initWithRed:0 green:0 blue:0 alpha:0]]];
    }
}

- (void)setActive:(BOOL)active
{
    if (_active == active) return;
    _active = active;
    if (active) {
        [self startAnimating];
    } else {
        [self stopAnimating];
    }
}

- (void)startAnimating
{
    // Invalidate any pending stop/hide callbacks.
    _stopGeneration++;
    [self layoutSubtreeIfNeeded];

    [_accumulator setImage:[CIImage imageWithColor:[[CIColor alloc] initWithRed:0 green:0 blue:0 alpha:0]]];

    _animating = YES;
    _lastTick = 0;
    _stopping = NO;
    _disappearing = NO;
    _disappearStart = 0;
    _disappearComplete = NO;
    _startTime = CFAbsoluteTimeGetCurrent();
    _angle = (CGFloat)-M_PI_2; // start at 12 o'clock
    if (self.hidden || self.alphaValue < 1.0) {
        self.hidden = NO;
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.1;
            self.animator.alphaValue = 1.0;
        } completionHandler:^{}];
    }
}

- (void)stopAnimating
{
    // Slow down over stopDuration, then fade quickly.
    if (_stopping || !_animating) {
        return;
    }
    _stopping = YES;
    _stopStart = CFAbsoluteTimeGetCurrent();
    NSUInteger generation = ++_stopGeneration;

    NSTimeInterval delay = _stopDuration + _disappearDuration;

    __weak PhosphorChaserView* weakSelf = self;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        PhosphorChaserView* strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        if (generation != strongSelf.stopGeneration) {
            return; // superseded by a new start/stop cycle
        }

        [NSAnimationContext runAnimationGroup:^(NSAnimationContext* context) {
            context.duration = strongSelf.fadeOutDuration;
            strongSelf.animator.alphaValue = 0.0;
        } completionHandler:^{
            if (generation != strongSelf.stopGeneration) {
                return;
            }
            strongSelf.animating = NO;
            strongSelf.stopping = NO;
            strongSelf.hidden = YES;
        }];
    });
}

- (void)tickWithTimestamp:(CFTimeInterval)timestamp
{
    if (!_animating) {
        return;
    }
    if (_lastTick == 0) {
        _lastTick = timestamp;
        return;
    }
    CFTimeInterval dt = timestamp - _lastTick;
    _lastTick = timestamp;
    if (dt <= 0) {
        return;
    }
    [self renderWithDelta:dt];
}

- (void)renderWithDelta:(CFTimeInterval)dt
{
    [self rebuildAccumulatorIfNeeded];

    if (!_accumulator || !_ciContext) {
        return;
    }

    // Advance angle clockwise based on period.
    CGFloat omega = (CGFloat)(2 * M_PI / MAX(_period, 0.1));
    CFTimeInterval now = CFAbsoluteTimeGetCurrent();
    // Ramp up speed after start.
    CGFloat rampScale = 1.0;
    if (_startTime > 0) {
        CGFloat rampT = (CGFloat)((now - _startTime) / MAX(_startRampDuration, 0.001));
        rampT = MIN(1.0, MAX(0.0, rampT));
        // smoothstep easing for a gentle ease-in to speed
        rampScale = rampT * rampT * (3.0f - 2.0f * rampT);
        if (rampT >= 1.0f) {
            _startTime = 0; // done ramping
        }
    }
    omega *= rampScale;
    if (_stopping) {
        CGFloat t = (CGFloat)((now - _stopStart) / MAX(_stopDuration, 0.001));
        // Smoothstep easing for a gentler slow-down.
        CGFloat eased = 1.0f - (t * t * (3.0f - 2.0f * t));
        CGFloat speedScale = MAX(0.0, eased);
        omega *= speedScale;
        // When fully stopped, trigger disappear phase.
        if (!_disappearing && t >= 1.0f) {
            _disappearing = YES;
            _disappearStart = now;
            _disappearComplete = NO;
        }
    }
    _angle += omega * dt;

    CGRect b = self.bounds;
    // Radius ramp in/out: grow from small start, shrink on stop.
    CGFloat radiusScale = 1.0;
    if (_startTime > 0 || rampScale < 1.0) {
        CGFloat rt = (CGFloat)((now - _startTime) / MAX(_radiusRampDuration, 0.001));
        rt = MIN(1.0f, MAX(0.0f, rt));
        // use same smoothstep easing for radius growth
        CGFloat eased = rt * rt * (3.0f - 2.0f * rt);
        radiusScale *= (0.25f + 0.75f * eased);
    }
    if (_stopping) {
        CGFloat t = (CGFloat)((now - _stopStart) / MAX(_stopDuration, 0.001));
        // Use the same smooth easing shape as speed to allow full collapse to zero.
        CGFloat eased = 1.0f - (t * t * (3.0f - 2.0f * t));
        CGFloat shrink = MAX(0.0f, eased);
        radiusScale *= shrink;
    }
    CGFloat disappearScale = 1.0f;
    if (_disappearing) {
        CGFloat dtDisappear = (CGFloat)((now - _disappearStart) / MAX(_disappearDuration, 0.001));
        disappearScale = MAX(0.0f, 1.0f - MIN(1.0f, dtDisappear));
        if (dtDisappear >= 1.0f) {
            _disappearing = NO;
            _disappearComplete = YES;
        }
    } else if (_disappearComplete) {
        disappearScale = 0.0f;
        if (_accumulator) {
            CIImage* clearImage = [CIImage imageWithColor:[[CIColor alloc] initWithRed:0 green:0 blue:0 alpha:0]];
            clearImage = [clearImage imageByCroppingToRect:_accumulator.extent];
            [_accumulator setImage:clearImage];
        }
        self.layer.contents = nil;
        _animating = NO;
        self.hidden = YES;
        return;
    }

    if (disappearScale <= 0.01f) {
        // Fully shrunken: ensure nothing renders.
        if (_accumulator) {
            CIImage* clearImage = [CIImage imageWithColor:[[CIColor alloc] initWithRed:0 green:0 blue:0 alpha:0]];
            clearImage = [clearImage imageByCroppingToRect:_accumulator.extent];
            [_accumulator setImage:clearImage];
        }
        self.layer.contents = nil;
        _animating = NO;
        self.hidden = YES;
        return;
    }

    CGFloat margin = 4.0;
    CGRect inset = CGRectInset(b, margin, margin);
    CGPoint insetCenter = CGPointMake(CGRectGetMidX(inset), CGRectGetMidY(inset));
    // Use a single base radius so circle and eight share the same envelope.
    CGFloat r = MIN(inset.size.width, inset.size.height) * 0.2;

    CGPoint headPos = CGPointMake(insetCenter.x + r * 0.85 * cos(_angle),
                                  insetCenter.y + r * 0.85 * sin(_angle));
    insetCenter = CGPointMake(CGRectGetMidX(b), CGRectGetMidY(b));
    headPos.x = insetCenter.x + (headPos.x - insetCenter.x) * radiusScale;
    headPos.y = insetCenter.y + (headPos.y - insetCenter.y) * radiusScale;
    // Core Image is unflipped; convert y so the dot is placed correctly.
    CGPoint headPosCI = CGPointMake(headPos.x, b.size.height - headPos.y);

    CIImage* prev = _accumulator.image;

    // Decay the previous image to create smear fade.
    CIFilter* decay = [CIFilter filterWithName:@"CIColorMatrix"];
    [decay setDefaults];
    [decay setValue:[CIVector vectorWithX:1 Y:0 Z:0 W:0] forKey:@"inputRVector"];
    [decay setValue:[CIVector vectorWithX:0 Y:1 Z:0 W:0] forKey:@"inputGVector"];
    [decay setValue:[CIVector vectorWithX:0 Y:0 Z:1 W:0] forKey:@"inputBVector"];
    [decay setValue:[CIVector vectorWithX:0 Y:0 Z:0 W:_decayFactor] forKey:@"inputAVector"];
    [decay setValue:[CIVector vectorWithX:0 Y:0 Z:0 W:0] forKey:@"inputBiasVector"];
    [decay setValue:prev forKey:kCIInputImageKey];
    CIImage *decayed = decay.outputImage;

    // Draw the head as a blurred radial gradient cropped to a small rect.
    CGColorRef beam = [[Defaults sharedDefaults] lightFakeBeamColor].CGColor;
    CIColor *beamCI = [[CIColor alloc] initWithCGColor:beam];
    CGFloat dotRadius = MAX(0.0f, 1.2f * disappearScale);
    CIFilter *head = [CIFilter filterWithName:@"CIRadialGradient"
                                keysAndValues:
                            @"inputCenter", [CIVector vectorWithX:headPosCI.x Y:headPosCI.y],
                            @"inputRadius0", @(0.0),
                            @"inputRadius1", @(dotRadius),
                            @"inputColor0", beamCI,
                            @"inputColor1", [[CIColor alloc] initWithRed:beamCI.red green:beamCI.green blue:beamCI.blue alpha:0.0],
                            nil];
    CGRect dotCrop = CGRectMake(headPosCI.x - (dotRadius + 3.0),
                                headPosCI.y - (dotRadius + 3.0),
                                (dotRadius + 3.0) * 2.0,
                                (dotRadius + 3.0) * 2.0);
    CIImage *dot = [head.outputImage imageByCroppingToRect:dotCrop];
    // Keep the core crisp for a 1px-like tail (no blur here).

    // Composite dot over decayed tail (this is what we keep in the accumulator).
    CIFilter *over = [CIFilter filterWithName:@"CISourceOverCompositing"];
    [over setValue:dot forKey:kCIInputImageKey];
    [over setValue:decayed forKey:kCIInputBackgroundImageKey];
    CIImage *tailImage = over.outputImage;

    // Apply warm tint gradient around the ring for the tail hue shift.
    CIColor *smearCI = [[CIColor alloc] initWithCGColor:[[Defaults sharedDefaults] regularFakeBeamColor].CGColor];
    CIFilter *tint = [CIFilter filterWithName:@"CIColorPolynomial"];
    [tint setValue:[CIVector vectorWithX:smearCI.red Y:0 Z:0 W:0] forKey:@"inputRedCoefficients"];
    [tint setValue:[CIVector vectorWithX:smearCI.green Y:0 Z:0 W:0] forKey:@"inputGreenCoefficients"];
    [tint setValue:[CIVector vectorWithX:smearCI.blue Y:0 Z:0 W:0] forKey:@"inputBlueCoefficients"];
    // Preserve alpha (no constant bias), avoid forcing the tail fully opaque.
    [tint setValue:[CIVector vectorWithX:0 Y:1 Z:0 W:0] forKey:@"inputAlphaCoefficients"];
    [tint setValue:tailImage forKey:kCIInputImageKey];
    CIImage *tailTinted = tint.outputImage;

    // Store ONLY the tail in the accumulator (no bloom/head replication).
    tailTinted = [tailTinted imageByCroppingToRect:_accumulator.extent];
    [_accumulator setImage:tailTinted];

    // Reinforce the head so it stays bright yellow at the tip (display only).
    CGFloat headSpotSize = MAX(0.0f, 4.0f * disappearScale);
    
    if (_stopping) {
        CGFloat t = (CGFloat)((now - _stopStart) / MAX(_stopDuration, 0.001));
        CGFloat shrink = MAX(0.25f, 1.0f - MIN(1.0f, t));
        radiusScale *= shrink;
    }

    CIFilter* headSpotGradient = [CIFilter filterWithName:@"CIRadialGradient" keysAndValues:
                                    @"inputCenter", [CIVector vectorWithX:headPosCI.x Y:headPosCI.y],
                                    @"inputRadius0", @(headSpotSize),
                                    @"inputRadius1", @(headSpotSize),
                                    @"inputColor0", [[CIColor alloc] initWithCGColor:beam],
                                    @"inputColor1", [[CIColor alloc] initWithCGColor:beam],
                                   nil];
    CGRect headRect = CGRectMake(headPosCI.x - headSpotSize * 0.5,
                                 headPosCI.y - headSpotSize * 0.5,
                                 headSpotSize,
                                 headSpotSize);
    CIImage *headSpot = [headSpotGradient.outputImage imageByCroppingToRect:headRect];
    // Keep bloom presence even as the dot shrinks; do not scale bloom parameters.
    headSpot = [headSpot imageByApplyingFilter:@"CIBloom" withInputParameters:@{@"inputRadius": @3.0, @"inputIntensity": @1.0}];

    CIFilter *headOver = [CIFilter filterWithName:@"CISourceOverCompositing"];
    [headOver setValue:headSpot forKey:kCIInputImageKey];
    [headOver setValue:tailTinted forKey:kCIInputBackgroundImageKey];
    CIImage *displayImage = headOver.outputImage;
    displayImage = [displayImage imageByApplyingFilter:@"CIBloom" withInputParameters:@{@"inputRadius": @4.0, @"inputIntensity": @1.0}];

    // Render to layer contents.
    // Render only the visible bounds.
    displayImage = [displayImage imageByCroppingToRect:b];
    CGImageRef cg = [_ciContext createCGImage:displayImage fromRect:b];
    self.layer.contents = (__bridge id)cg;
    if (cg) {
        CGImageRelease(cg);
    }
}

@end
