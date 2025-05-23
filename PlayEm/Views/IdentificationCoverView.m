//
//  IdentificationActiveView.m
//  PlayEm
//
//  Created by Till Toenshoff on 10.06.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import "IdentificationCoverView.h"
#import <Quartz/Quartz.h>
#import <CoreImage/CoreImage.h>
#import <CoreImage/CIFilterBuiltins.h>

#import "../Sample/BeatEvent.h"
#import "CAShapeLayer+Path.h"
#import "CALayer+PauseAnimations.h"
#import "../Defaults.h"
#import "../NSBezierPath+CGPath.h"
#import "../NSImage+Resize.h"
#import "../Audio/AudioProcessing.h"
#import "../NSImage+Average.h"

//#define HIDE_COVER_DEBBUG 1

static NSString * const kLayerImageName = @"IdentificationActiveStill";
static NSString * const kLayerMaskImageName = @"IdentificationActiveStill";
extern NSString * const kBeatTrackedSampleTempoChangeNotification;

@interface IdentificationCoverView ()
@property (nonatomic, strong) CALayer* imageLayer;
@property (nonatomic, strong) CALayer* imageCopyLayer;
@property (nonatomic, strong) CALayer* maskLayer;
@property (nonatomic, strong) CALayer* overlayLayer;
@property (nonatomic, strong) CALayer* glowLayer;
@property (nonatomic, strong) CALayer* heloLayer;
//@property (nonatomic, strong) CALayer* glowMaskLayer;
@property (nonatomic, strong) CALayer* finalFxLayer;
@end

@implementation IdentificationCoverView
{
    float currentTempo;
    BOOL animating;
    BOOL paused;
    BOOL unknown;
    double lastEnergy;
}

- (id)initWithFrame:(NSRect)frameRect contentsInsets:(NSEdgeInsets)insets style:(CoverViewStyleMask)style
{
    self = [super initWithFrame:frameRect];
    if (self) {
        animating = NO;
        paused = NO;
        unknown = YES;
        currentTempo = 120.0f;
        lastEnergy = 0.0;
        _overlayIntensity = 0.3f;
        _secondImageLayerOpacity = 0.2;
        _style = style;
        self.additionalSafeAreaInsets = insets;
        self.wantsLayer = YES;
        self.autoresizingMask = NSViewHeightSizable | NSViewWidthSizable;
        self.clipsToBounds = NO;
        self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;
        self.layerUsesCoreImageFilters = YES;

        if ((style & CoverViewStyleRotatingLaser) == CoverViewStyleRotatingLaser) {
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(tempoChange:) name:kBeatTrackedSampleTempoChangeNotification object:nil];
        }
        if ((style & CoverViewStylePumpingToTheBeat) == CoverViewStylePumpingToTheBeat) {
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(beatEffect:) name:kBeatTrackedSampleBeatNotification object:nil];
        }
    }
    return self;
}

- (BOOL)allowsVibrancy
{
    return YES;
}

- (void)tempoChange:(NSNotification*)notification
{
    NSNumber* tempo = notification.object;
    float value = [tempo floatValue];
    if (value > 0.0) {
        currentTempo = value;
    }
}

- (void)beatPumpingLayer:(CALayer*)layer localEnergy:(double)localEnergy totalEnergy:(double)totalEnergy
{
    const CGSize halfSize = CGSizeMake(layer.bounds.size.width / 2.0, layer.bounds.size.height / 2.0);

    if (localEnergy == 0.0) {
        localEnergy = 0.000000001;
    }
    const double depth = 3.0f;
    // Attempt to get a reasonably wide signal range by normalizing the locals peaks by
    // the globally most energy loaded samples.
    const double normalizedEnergy = MIN(localEnergy / totalEnergy, 1.0);

    // We quickly attempt to reach a value that is higher than the current one.
    const double convergenceSpeedUp = 0.8;
    // We slowly decay into a value that is lower than the current one.
    const double convergenceSlowDown = 0.08;

    double convergenceSpeed = normalizedEnergy > lastEnergy ? convergenceSpeedUp : convergenceSlowDown;
    // To make sure the result is not flapping we smooth (lerp) using the previous result.
    double lerpEnergy = (normalizedEnergy * convergenceSpeed) + lastEnergy *  (1.0 - convergenceSpeed);
    // Gate the result for safety -- may mathematically not be needed, too lazy to find out.
    double slopedEnergy = MIN(lerpEnergy, 1.0);
    
    lastEnergy = slopedEnergy;
    
    CGFloat scaleByPixel = slopedEnergy * depth;
    double peakZoomBlurAmount = (scaleByPixel  * scaleByPixel) / 2.0;
    
    // We want to have an enlarged image the moment the beat hits, thus we start large as
    // that is when we are beeing called within the phase of the rhythm.
    CATransform3D tr = CATransform3DIdentity;
    CGFloat scaleByFactor = 1.0 / (layer.bounds.size.width / scaleByPixel);
    tr = CATransform3DTranslate(tr, halfSize.width, halfSize.height, 0.0);
    tr = CATransform3DScale(tr, 1.0 + scaleByFactor, 1.0 + scaleByFactor, 1.0);
    tr = CATransform3DTranslate(tr, -halfSize.width, -halfSize.height, 0.0);
    
    layer.transform = tr;
    
    CABasicAnimation* animation = [CABasicAnimation animationWithKeyPath:@"transform"];
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    animation.fillMode = kCAFillModeBoth;
    animation.removedOnCompletion = NO;
    double phaseLength = 30.0f / self->currentTempo;
    animation.fromValue = [NSValue valueWithCATransform3D:tr];
    animation.toValue = [NSValue valueWithCATransform3D:CATransform3DIdentity];
    animation.repeatCount = 1.0f;
    animation.autoreverses = YES;
    animation.duration = phaseLength;
    animation.removedOnCompletion = NO;
    [layer addAnimation:animation forKey:@"beatPumping"];
    
    animation = [CABasicAnimation animationWithKeyPath:@"backgroundFilters.CIZoomBlur.inputAmount"];
    animation.fromValue = @(peakZoomBlurAmount);
    animation.toValue = @(0.0);
    animation.repeatCount = 1.0f;
    animation.autoreverses = YES;
    animation.duration = phaseLength;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    animation.fillMode = kCAFillModeBoth;
    animation.removedOnCompletion = NO;
    [_finalFxLayer addAnimation:animation forKey:@"beatWarping"];
    
    animation = [CABasicAnimation animationWithKeyPath:@"opacity"];
    // We want the lighting to be very dimm for low values and to only become prominent with
    // enery levels way above 50%.
    float glowQuantum = powf(slopedEnergy, 5);
    animation.fromValue = @(glowQuantum);
    animation.toValue = @(0.0);
    animation.repeatCount = 1.0f;
    animation.autoreverses = YES;
    animation.duration = phaseLength;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    animation.fillMode = kCAFillModeBoth;
    animation.removedOnCompletion = NO;
    [_heloLayer addAnimation:animation forKey:@"cornerFlashing"];
}

- (void)beatShakingLayer:(CALayer*)layer
{
    static BOOL forward = YES;
    const int moveBeats = 4;
    
    const CGFloat phaseLength = (60.0 * (moveBeats / 2.0)) / self->currentTempo;
    CGFloat angleToAdd = M_PI_2 / 90.0;
    
    forward = !forward;
    
    if (!forward)  {
        angleToAdd = angleToAdd * -1.0;
    }
    
    CABasicAnimation* animation = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    animation.toValue = @(angleToAdd);
    animation.fromValue = @(0.0);
    animation.repeatCount = 1.0f;
    animation.autoreverses = YES;
    animation.duration = phaseLength;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    animation.fillMode = kCAFillModeBoth;
    animation.removedOnCompletion = NO;
    
    [layer addAnimation:animation forKey:@"beatShaking"];
}

- (void)beatEffect:(NSNotification*)notification
{
    const NSDictionary* dict = notification.object;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    // Bomb the bass!
    [self beatPumpingLayer:self.layer
               localEnergy:[dict[kBeatNotificationKeyLocalEnergy] doubleValue]
               totalEnergy:[dict[kBeatNotificationKeyTotalEnergy] doubleValue]];

    // We start shaking only on the first beat of a bar.
    if ([dict[kBeatNotificationKeyBeat] intValue] == 1) {
        [self beatShakingLayer:_backingLayer];
    }
    
    [CATransaction commit];
}

- (CGImageRef)lightTunnelFilterImage:(CGImageRef)inputImage
                     withInputCenter:(CGPoint)center
                       inputRotation:(CGFloat)rotation
                         inputRadius:(CGFloat)radius
{
    CIFilter<CILightTunnel>* tunnelFilter = CIFilter.lightTunnelFilter;
    tunnelFilter.inputImage = [CIImage imageWithCGImage:inputImage];
    tunnelFilter.center = center;
    tunnelFilter.rotation = rotation;
    tunnelFilter.radius = radius;
    return [tunnelFilter.outputImage CGImage];
}

- (CALayer*)makeBackingLayer
{
    CALayer* layer = [CALayer layer];
    layer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    layer.frame = self.bounds;
    layer.masksToBounds = NO;
    layer.anchorPoint = CGPointMake(0.5, 0.5);
    
    CGRect contentsBounds = CGRectMake(0.0, 0.0, self.bounds.size.width - (self.additionalSafeAreaInsets.left + self.additionalSafeAreaInsets.right), self.bounds.size.height - (self.additionalSafeAreaInsets.top + self.additionalSafeAreaInsets.bottom));
    CGRect contentsFrame = CGRectMake(self.additionalSafeAreaInsets.left, self.additionalSafeAreaInsets.top, self.bounds.size.width - (self.additionalSafeAreaInsets.left + self.additionalSafeAreaInsets.right), self.bounds.size.height - (self.additionalSafeAreaInsets.top + self.additionalSafeAreaInsets.bottom));
    //CGRect contentsFrame = CGRectInset(self.bounds, self.additionalSafeAreaInsets.left, self.additionalSafeAreaInsets.top);

    CIFilter* bloomFilter = [CIFilter filterWithName:@"CIBloom"];
    [bloomFilter setDefaults];
    [bloomFilter setValue: [NSNumber numberWithFloat:7.0] forKey: @"inputRadius"];
    [bloomFilter setValue: [NSNumber numberWithFloat:1.0] forKey: @"inputIntensity"];

    CIFilter* additionFilter = [CIFilter filterWithName:@"CIAdditionCompositing"];
    [additionFilter setDefaults];

    if ((_style & CoverViewStyleGlowBehindCoverAtLaser) == CoverViewStyleGlowBehindCoverAtLaser) {
        _heloLayer = [CALayer layer];
        _heloLayer.magnificationFilter = kCAFilterLinear;
        _heloLayer.minificationFilter = kCAFilterLinear;
        NSImage* input = [NSImage resizedImage:[NSImage imageNamed:@"HeloGlow"]
                                 size:contentsBounds.size];
        _heloLayer.contents = input;
        
        //_glowLayer.contents = [self lightTunnelFilterImage:[input CG] withInputCenter:CGPointMake(self.bounds.size.width / 2.0, self.bounds.size.height / 2.0) inputRotation:0.0 inputRadius:0.0];
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

        _glowLayer = [CALayer layer];
        _glowLayer.magnificationFilter = kCAFilterLinear;
        _glowLayer.minificationFilter = kCAFilterLinear;
        input = [NSImage resizedImage:[NSImage imageNamed:@"FadeGlow"]
                                            size:contentsBounds.size];
        _glowLayer.contents = input;
        
        //_glowLayer.contents = [self lightTunnelFilterImage:[input CG] withInputCenter:CGPointMake(self.bounds.size.width / 2.0, self.bounds.size.height / 2.0) inputRotation:0.0 inputRadius:0.0];
        _glowLayer.frame = CGRectInset(contentsFrame, -100.0, -100.0);
    //    _glowLayer.frame = CGRectOffset(_glowLayer.frame, -50.0, -50.0);
        _glowLayer.allowsEdgeAntialiasing = YES;
        _glowLayer.shouldRasterize = YES;
        _glowLayer.opacity = 0.6f;
        _glowLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
        _glowLayer.rasterizationScale = layer.contentsScale;
        _glowLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
        _glowLayer.backgroundFilters = @[ bloomFilter ];
        _glowLayer.masksToBounds = YES;
        _glowLayer.filters = @[ bloomFilter ];
        _glowLayer.compositingFilter = additionFilter;
        [layer addSublayer:_glowLayer];
    }

    // A layer meant to assert that our cover pops out and has maximal contrast. We need
    // this because <FIXME: Why?>
    _backingLayer = [CALayer layer];
    _backingLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    _backingLayer.frame = contentsFrame;
    _backingLayer.shouldRasterize = YES;
    _backingLayer.masksToBounds = NO;
    _backingLayer.cornerRadius = 7.0f;
    _backingLayer.anchorPoint = CGPointMake(0.5, 0.5);
    _backingLayer.allowsEdgeAntialiasing = YES;
    _backingLayer.magnificationFilter = kCAFilterLinear;
    _backingLayer.minificationFilter = kCAFilterLinear;
    _backingLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
//    _backingLayer.contents = [NSImage resizedImage:[NSImage imageNamed:@"UnknownSong"]
//                                            size:self.bounds.size];
//    
//    if ((_style & CoverViewStyleRotatingLaser) == CoverViewStyleRotatingLaser) {
//        _backingLayer.filt = @[ darkFilter     ];
//    }

    //_backingLayer.backgroundColor = [NSColor blackColor].CGColor;
    _backingLayer.backgroundColor = [NSColor controlBackgroundColor].CGColor;
    //_backingLayer.backgroundColor = [NSColor blackColor].CGColor;

    _maskLayer = [CALayer layer];
    _maskLayer.contents = [NSImage imageNamed:@"FadeMask"];
    _maskLayer.frame = CGRectMake(-contentsBounds.size.width / 2, -contentsBounds.size.height / 2, contentsBounds.size.width * 2, contentsBounds.size.height * 2);
    _maskLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    _maskLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    _maskLayer.allowsEdgeAntialiasing = YES;
    _maskLayer.position = CGPointMake(contentsBounds.size.width / 2, contentsBounds.size.height / 2);
    
    _imageCopyLayer = [CALayer layer];
    _imageCopyLayer.magnificationFilter = kCAFilterLinear;
    _imageCopyLayer.minificationFilter = kCAFilterLinear;
    _imageCopyLayer.frame = contentsBounds;
    _imageCopyLayer.contents = [NSImage resizedImage:[NSImage imageNamed:@"UnknownSong"]
                                                size:contentsBounds.size];
    _imageCopyLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    _imageCopyLayer.cornerRadius = 7.0f;
    _imageCopyLayer.allowsEdgeAntialiasing = YES;
    _imageCopyLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    _imageCopyLayer.frame = contentsBounds;
    _imageCopyLayer.mask = _maskLayer;
    _imageCopyLayer.masksToBounds = YES;
    if ((_style & CoverViewStyleGlowBehindCoverAtLaser) == CoverViewStyleGlowBehindCoverAtLaser) {
        _imageCopyLayer.borderWidth = 1.0;
        //_imageLayer.borderColor = [NSColor windowFrameColor].CGColor;
        _imageCopyLayer.borderColor = [[Defaults sharedDefaults] regularBeamColor].CGColor;
    }

    if ((_style & CoverViewStyleSepiaForSecondImageLayer) == CoverViewStyleSepiaForSecondImageLayer) {
        CIFilter* sepia = [CIFilter filterWithName:@"CISepiaTone"];
        [sepia setDefaults];
        _imageCopyLayer.filters = @[ sepia ];
    }
    _imageCopyLayer.opacity = _secondImageLayerOpacity;
    [_backingLayer addSublayer:_imageCopyLayer];

    _imageLayer = [CALayer layer];
    _imageLayer.magnificationFilter = kCAFilterLinear;
    _imageLayer.minificationFilter = kCAFilterLinear;
    _imageLayer.frame = contentsBounds;
    _imageLayer.contents = [NSImage resizedImage:[NSImage imageNamed:@"UnknownSong"]
                                            size:contentsBounds.size];
    _imageLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    _imageLayer.allowsEdgeAntialiasing = YES;
    _imageLayer.shouldRasterize = YES;
    _imageLayer.rasterizationScale = layer.contentsScale;
    _imageLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    _imageLayer.cornerRadius = 7.0f;
    _imageLayer.frame = contentsBounds;
    _imageLayer.masksToBounds = YES;
    if ((_style & CoverViewStyleGlowBehindCoverAtLaser) == CoverViewStyleGlowBehindCoverAtLaser) {
        _imageLayer.borderWidth = 1.0;
        //_imageLayer.borderColor = [NSColor windowFrameColor].CGColor;
        _imageLayer.borderColor = [[[Defaults sharedDefaults] lightBeamColor] colorWithAlphaComponent:0.3].CGColor;
    }
    if ((_style & CoverViewStyleRotatingLaser) == CoverViewStyleRotatingLaser) {
        _imageLayer.mask = _maskLayer;
    }

    CIFilter* fxFilter = [CIFilter filterWithName:@"CIZoomBlur"];
    [fxFilter setDefaults];
    //CGPoint center = CGPointMake(contentsBounds.size.width / 2.0f, contentsBounds.size.height / 2.0f);
    [fxFilter setValue: [NSNumber numberWithFloat:0.0] forKey: @"inputAmount"];
    //[fxFilter setValue: [NSValue valueWithPoint:center] forKey: @"inputCenter"];
    //[fxFilter setValue: [NSNumber numberWithFloat:0.1] forKey: @"inputScale"];

    if ((_style & CoverViewStyleRotatingLaser) == CoverViewStyleRotatingLaser) {
        _imageLayer.filters = @[ bloomFilter ];
    }
    [_backingLayer addSublayer:_imageLayer];

    if ((_style & CoverViewStyleRotatingLaser) == CoverViewStyleRotatingLaser) {
        _overlayLayer = [CALayer layer];
        _overlayLayer.contents = [NSImage imageNamed:kLayerImageName];
        _overlayLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
        _overlayLayer.shouldRasterize = YES;
        _overlayLayer.cornerRadius = 7.0f;
        _overlayLayer.allowsEdgeAntialiasing = YES;
        _overlayLayer.rasterizationScale = layer.contentsScale;
        _overlayLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
        _overlayLayer.magnificationFilter = kCAFilterLinear;
        _overlayLayer.minificationFilter = kCAFilterLinear;
        _overlayLayer.opacity = _overlayIntensity;
        _overlayLayer.anchorPoint = CGPointMake(0.5, 0.507);
        _overlayLayer.frame = _maskLayer.frame;
        _overlayLayer.compositingFilter = additionFilter;
        [_imageLayer addSublayer:_overlayLayer];

//        _overlayLayer.backgroundFilters = @[ fxFilter ];
    }

    
#ifndef HIDE_COVER_DEBBUG
    [layer addSublayer:_backingLayer];
#endif
    _finalFxLayer = [CALayer layer];
    _finalFxLayer.frame = contentsBounds;
    _finalFxLayer.backgroundFilters = @[ fxFilter];
    
    [_backingLayer addSublayer:_finalFxLayer];
    

//    NSImage* image = [NSImage resizedImage:[NSImage imageNamed:@"UnknownSong"] size:self.bounds.size];
//    CIImage* ciImage = [CIImage imageWithCGImage:[image CGImageForProposedRect:nil context:nil hints:nil]];
//    [fxFilter setValue:ciImage forKey: @"inputImage"];

//        _finalFxLayer = [CALayer layer];
//        //_glowLayer.contents = [self lightTunnelFilterImage:[input CG] withInputCenter:CGPointMake(self.bounds.size.width / 2.0, self.bounds.size.height / 2.0) inputRotation:0.0 inputRadius:0.0];
//        _finalFxLayer.frame = CGRectInset(self.bounds, -100.0, -100.0);
//    //    _glowLayer.frame = CGRectOffset(_glowLayer.frame, -50.0, -50.0);
//        _finalFxLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
//        _finalFxLayer.masksToBounds = YES;
//        [_overlayLayer addSublayer:_finalFxLayer];
//    //}
//    
    //    //if ((_style & CoverViewStyleGlowBehindCoverAtLaser) == CoverViewStyleGlowBehindCoverAtLaser) {

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
    animation.fromValue = (id)layer.presentationLayer.backgroundColor;
    animation.toValue = (id)color.CGColor;
    animation.repeatCount = 1.0f;
    animation.autoreverses = NO;
    animation.duration = 4.0f;
    [layer addAnimation:animation forKey:@"BackgroundColorTransition"];
}

- (void)setImage:(NSImage*)image animated:(BOOL)animated
{
    NSColor* averageColor = nil;
    if (image == nil) {
        unknown = YES;
        image = [NSImage imageNamed:@"UnknownSong"];
        averageColor = [NSColor windowBackgroundColor];
    } else {
        unknown = NO;
        averageColor = [image averageColor];
    }

    if (animated) {
        [self animateLayer:self.layer toBackgroundColor:averageColor];

        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            [context setDuration:2.1f];
            [context setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn]];
            self.animator.imageCopyLayer.contents = image;
            self.animator.imageLayer.contents = image;
        }];
    } else {
        [self.layer removeAllAnimations];

        self.imageCopyLayer.contents = image;
        self.imageLayer.contents = image;
    }

    self.layer.backgroundColor = averageColor.CGColor;
}

- (void)animate
{
    if ((_style & (CoverViewStyleRotatingLaser | CoverViewStyleGlowBehindCoverAtLaser)) == 0) {
        return;
    }
    
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
        if ((_style & CoverViewStyleRotatingLaser) == CoverViewStyleRotatingLaser) {
            [_overlayLayer setValue:@(M_PI_2 * beatsPerCycle) forKeyPath:@"transform.rotation.z"];
            [_maskLayer setValue:@(M_PI_2 * beatsPerCycle) forKeyPath:@"transform.rotation.z"];
        }
        if ((_style & CoverViewStyleGlowBehindCoverAtLaser) == CoverViewStyleGlowBehindCoverAtLaser) {
            [_glowLayer setValue:@(M_PI_2 * beatsPerCycle) forKeyPath:@"transform.rotation.z"];
        }
        animation.toValue = @(0.0);
        animation.byValue = @(angleToAdd);
        animation.repeatCount = 1.0f;
        [CATransaction setCompletionBlock:^{
            if (!self->animating) {
                NSLog(@"we are not animating anymore!!!!");
                return;
            }
            [self animate];
        }];
        if ((_style & CoverViewStyleRotatingLaser) == CoverViewStyleRotatingLaser) {
            [_overlayLayer addAnimation:animation forKey:@"rotation"];
            [_maskLayer addAnimation:animation forKey:@"rotation"];
        }
        if ((_style & CoverViewStyleGlowBehindCoverAtLaser) == CoverViewStyleGlowBehindCoverAtLaser) {
            [_glowLayer addAnimation:animation forKey:@"rotation"];
        }
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

- (NSBezierPath*)shadowPathForRect:(CGRect)rect
{
    const CGFloat kCoverCornerRadius = 7.0;
    const CGFloat tr = kCoverCornerRadius;
    const CGFloat tl = kCoverCornerRadius;
    const CGFloat br = kCoverCornerRadius;
    const CGFloat bl = kCoverCornerRadius;

    //selectionRect = NSOffsetRect(selectionRect, -20.0, -20.0);

    NSBezierPath* path = [NSBezierPath bezierPath];
    
    [path moveToPoint:CGPointMake(rect.origin.x + tl, rect.origin.y)];
    [path lineToPoint:CGPointMake(rect.origin.x + rect.size.width - tr, rect.origin.y)];
    [path appendBezierPathWithArcWithCenter:CGPointMake(rect.origin.x + rect.size.width - tr, rect.origin.y + tr)
                                     radius:tr
                                 startAngle:-90.0
                                   endAngle:0.0
                                  clockwise:NO];
    [path lineToPoint:CGPointMake(rect.origin.x + rect.size.width, rect.origin.y + rect.size.height - br)];
    [path appendBezierPathWithArcWithCenter:CGPointMake(rect.origin.x + rect.size.width - br, rect.origin.y + rect.size.height - br)
                                     radius:br
                                 startAngle:0.0
                                   endAngle:90.0
                                  clockwise:NO];

    [path lineToPoint:CGPointMake(rect.origin.x + bl, rect.origin.y + rect.size.height)];
    [path appendBezierPathWithArcWithCenter:CGPointMake(rect.origin.x + bl, rect.origin.y + rect.size.height - bl)
                                     radius:bl
                                 startAngle:90.0
                                   endAngle:180.0
                                  clockwise:NO];

    [path lineToPoint:CGPointMake(rect.origin.x, rect.origin.y + tl)];
    [path appendBezierPathWithArcWithCenter:CGPointMake(rect.origin.x + tl, rect.origin.y + tl)
                                     radius:tl
                                 startAngle:180.0
                                   endAngle:270.0
                                  clockwise:NO];

    return path;
}

//- (void)drawLayer:(CALayer*)layer inContext:(CGContextRef)context
//{
//    CGContextSetAllowsAntialiasing(context, YES);
//    CGContextSetShouldAntialias(context, YES);
//    
//    CGColorRef shadowColor = [[[Defaults sharedDefaults] lightBeamColor] CGColor];
//
//    CGContextSetShadowWithColor(context,
//                                CGSizeMake(0.0, 0.0),
//                                20.0,
//                                shadowColor);
//
//    NSBezierPath* path = [self shadowPathForRect:NSInsetRect(layer.frame, 20.0, 20.0)];
//    CGPathRef p = [NSBezierPath CGPathFromPath:path];
//
//    CGContextSetStrokeColorWithColor(context, shadowColor);
//    CGContextSetFillColorWithColor(context, shadowColor);
//    CGContextAddPath(context, p);
//    CGContextFillPath(context);
//    CGPathRelease(p);
//}

@end
