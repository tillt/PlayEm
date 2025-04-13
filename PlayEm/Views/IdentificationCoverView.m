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

static NSString * const kLayerImageName = @"IdentificationActiveStill";
static NSString * const kLayerMaskImageName = @"IdentificationActiveStill";
extern NSString * const kBeatTrackedSampleTempoChangeNotification;

@interface IdentificationCoverView ()
@property (nonatomic, strong) CALayer* imageLayer;
@property (nonatomic, strong) CALayer* imageCopyLayer;
@property (nonatomic, strong) CALayer* maskLayer;
@property (nonatomic, strong) CALayer* overlayLayer;
@property (nonatomic, strong) CALayer* glowLayer;
@property (nonatomic, strong) CALayer* glowMaskLayer;
@end

@implementation IdentificationCoverView
{
    float currentTempo;
    BOOL animating;
    BOOL paused;
}

- (id)initWithFrame:(NSRect)frameRect style:(CoverViewStyleMask)style
{
    self = [super initWithFrame:frameRect];
    if (self) {
        animating = NO;
        paused = NO;
        currentTempo = 120.0f;
        _overlayIntensity = 0.3f;
        _secondImageLayerOpacity = 0.2;
        _style = style;

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

- (void)tempoChange:(NSNotification*)notification
{
    NSNumber* tempo = notification.object;
    float value = [tempo floatValue];
    if (value > 0.0) {
        currentTempo = value;
    }
}

- (void)beatEffect:(NSNotification*)notification
{
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
   
    CATransform3D tr = CATransform3DIdentity;
    
    CGFloat scaleByPixel = 3.0;
    CGFloat scaleByFactor = 1.0 / (self.bounds.size.width / scaleByPixel);
    
    CGSize halfSize = CGSizeMake(self.bounds.size.width / 2.0, self.bounds.size.height / 2.0);
    tr = CATransform3DTranslate(tr, halfSize.width, halfSize.height, 0.0);
    tr = CATransform3DScale(tr, 1.0 + scaleByFactor, 1.0 + scaleByFactor, 1.0);
    tr = CATransform3DTranslate(tr, -halfSize.width, -halfSize.height, 0.0);
    
    // We want to have an enlarged image the moment the beat hits, thus we start large as
    // that is when we are beeing called within the phase of the rhythm.
    self.layer.transform = tr;

    CABasicAnimation* animation = [CABasicAnimation animationWithKeyPath:@"transform"];
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    animation.fillMode = kCAFillModeBoth;
    animation.removedOnCompletion = NO;
    double phaseLength = 30.0f / self->currentTempo;
    animation.fromValue = [NSValue valueWithCATransform3D:tr];
    animation.toValue = [NSValue valueWithCATransform3D:CATransform3DIdentity];
    animation.repeatCount = 2.0f;
    animation.autoreverses = YES;
    animation.duration = phaseLength;
    [self.layer addAnimation:animation forKey:@"stuff1"];

//    animation = [CABasicAnimation animationWithKeyPath:@"shadowColor"];
//    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
//    animation.fillMode = kCAFillModeBoth;
//    animation.removedOnCompletion = NO;
//    
//    NSColor* light = [[Defaults sharedDefaults] lightBeamColor];
//    NSColor* regular = [[Defaults sharedDefaults] regularBeamColor];
//
//    animation.fromValue = (id)light.CGColor;
//    animation.toValue = (id)regular.CGColor;
//    animation.repeatCount = 2.0f;
//    animation.autoreverses = YES;
//    animation.duration = phaseLength;
//    [self.layer addAnimation:animation forKey:@"stuff2"];

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
    
    CIFilter* bloomFilter = [CIFilter filterWithName:@"CIBloom"];
    [bloomFilter setDefaults];
    [bloomFilter setValue: [NSNumber numberWithFloat:5.0] forKey: @"inputRadius"];
    [bloomFilter setValue: [NSNumber numberWithFloat:1.0] forKey: @"inputIntensity"];

    CIFilter* darkFilter = [CIFilter filterWithName:@"CILightTunnel"];
    [darkFilter setDefaults];
    [darkFilter setValue: [NSNumber numberWithFloat:0.0] forKey: @"inputRadius"];

    CIFilter* additionFilter = [CIFilter filterWithName:@"CIAdditionCompositing"];
    [additionFilter setDefaults];

    if ((_style & CoverViewStyleGlowBehindCoverAtLaser) == CoverViewStyleGlowBehindCoverAtLaser) {
        _glowLayer = [CALayer layer];
        _glowLayer.magnificationFilter = kCAFilterLinear;
        _glowLayer.minificationFilter = kCAFilterLinear;
        NSImage* input = [NSImage resizedImage:[NSImage imageNamed:@"FadeGlow"]
                                            size:self.bounds.size];
        _glowLayer.contents = input;
        
        //_glowLayer.contents = [self lightTunnelFilterImage:[input CG] withInputCenter:CGPointMake(self.bounds.size.width / 2.0, self.bounds.size.height / 2.0) inputRotation:0.0 inputRadius:0.0];
        _glowLayer.frame = CGRectInset(self.bounds, -100.0, -100.0);
    //    _glowLayer.frame = CGRectOffset(_glowLayer.frame, -50.0, -50.0);
        _glowLayer.allowsEdgeAntialiasing = YES;
        _glowLayer.shouldRasterize = YES;
        _glowLayer.rasterizationScale = layer.contentsScale;
        _glowLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
        _glowLayer.masksToBounds = YES;
//        _glowLayer.backgroundFilters = @[ bloomFilter ];
        //_glowLayer.compositingFilter = additionFilter;
        [layer addSublayer:_glowLayer];
    }

    // A layer meant to assert that our cover pops out and has maximal contrast. We need
    // this because <FIXME: Why?>
    _backingLayer = [CALayer layer];
    _backingLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    _backingLayer.frame = self.bounds;
    _backingLayer.shouldRasterize = YES;
    _backingLayer.masksToBounds = NO;
    _backingLayer.cornerRadius = 7.0f;
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

    _backingLayer.backgroundColor = [NSColor windowBackgroundColor].CGColor;
    //_backingLayer.backgroundColor = [NSColor blackColor].CGColor;

    _maskLayer = [CALayer layer];
    _maskLayer.contents = [NSImage imageNamed:@"FadeMask"];
    _maskLayer.frame = CGRectMake(-self.bounds.size.width / 2, -self.bounds.size.height / 2, self.bounds.size.width * 2, self.bounds.size.height * 2);
    _maskLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    _maskLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    _maskLayer.allowsEdgeAntialiasing = YES;
    _maskLayer.position = CGPointMake(self.bounds.size.width / 2, self.bounds.size.height / 2);
    
    _imageCopyLayer = [CALayer layer];
    _imageCopyLayer.magnificationFilter = kCAFilterLinear;
    _imageCopyLayer.minificationFilter = kCAFilterLinear;
    _imageCopyLayer.frame = self.bounds;
    _imageCopyLayer.contents = [NSImage resizedImage:[NSImage imageNamed:@"UnknownSong"]
                                                size:self.bounds.size];
    _imageCopyLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    _imageCopyLayer.cornerRadius = 7.0f;
    _imageCopyLayer.allowsEdgeAntialiasing = YES;
    _imageCopyLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    _imageCopyLayer.frame = self.bounds;
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
    _imageLayer.frame = self.bounds;
    _imageLayer.contents = [NSImage resizedImage:[NSImage imageNamed:@"UnknownSong"]
                                            size:self.bounds.size];
    //_imageLayer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    _imageLayer.allowsEdgeAntialiasing = YES;
    _imageLayer.shouldRasterize = YES;
    _imageLayer.rasterizationScale = layer.contentsScale;
    _imageLayer.contentsScale = [[NSScreen mainScreen] backingScaleFactor];
    _imageLayer.cornerRadius = 7.0f;
    _imageLayer.frame = self.bounds;
    _imageLayer.masksToBounds = YES;
    if ((_style & CoverViewStyleGlowBehindCoverAtLaser) == CoverViewStyleGlowBehindCoverAtLaser) {
        _imageLayer.borderWidth = 1.0;
        //_imageLayer.borderColor = [NSColor windowFrameColor].CGColor;
        _imageLayer.borderColor = [[Defaults sharedDefaults] lightBeamColor].CGColor;
    }
    if ((_style & CoverViewStyleRotatingLaser) == CoverViewStyleRotatingLaser) {
        _imageLayer.mask = _maskLayer;
    }
    if ((_style & CoverViewStyleRotatingLaser) == CoverViewStyleRotatingLaser) {
        _imageLayer.filters = @[ bloomFilter     ];
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
    }

    [layer addSublayer:_backingLayer];

    return layer;
}

- (void)setImage:(NSImage*)image
{
    [self setImage:image animated:YES];
}

- (void)setImage:(NSImage*)image animated:(BOOL)animated
{
    if (animated) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            [context setDuration:2.1f];
            [context setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn]];
            self.animator.imageCopyLayer.contents = image;
            self.animator.imageLayer.contents = image;
        }];
    } else {
        self.imageCopyLayer.contents = image;
        self.imageLayer.contents = image;
    }
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
