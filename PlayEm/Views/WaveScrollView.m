//
//  WaveScrollView.m
//  PlayEm
//
//  Created by Till Toenshoff on 8/23/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import <CoreImage/CoreImage.h>

#import "CAShapeLayer+Path.h"
#import "NSBezierPath+CGPath.h"


#import "Scroller.h"
#import "WaveScrollView.h"
#import "TileView.h"
#import "LazySample.h"
#import "VisualSample.h"
#import "Defaults.h"
#import "MarkLayerController.h"

@interface WaveScrollView () // Private
@end

@implementation WaveScrollView

- (nonnull instancetype)initWithFrame:(CGRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        Scroller* scroller = [Scroller new];
        scroller.color = [NSColor redColor];
        self.horizontalScroller = scroller;
        

        self.wantsLayer = YES;
        self.layerUsesCoreImageFilters = YES;
        self.layer = [self makeBackingLayer];
        self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;
//        self.layer.backgroundColor = [[NSColor blueColor] CGColor];





        self.automaticallyAdjustsContentInsets = NO;
        self.contentInsets = NSEdgeInsetsMake(0.0, 0.0, 0.0, 0.0);
        
        self.backgroundColor = [[Defaults sharedDefaults] backColor];
        
        self.allowsMagnification = NO;
        self.canDrawConcurrently = YES;
        
        self.horizontal = YES;
        

        CIFilter* vibranceFilter = [CIFilter filterWithName:@"CIColorControls"];
        [vibranceFilter setDefaults];
        [vibranceFilter setValue:[NSNumber numberWithFloat:0.10] forKey:@"inputSaturation"];
        [vibranceFilter setValue:[NSNumber numberWithFloat:0.0001] forKey:@"inputBrightness"];

        CIFilter* darkenFilter = [CIFilter filterWithName:@"CIGammaAdjust"];
        [darkenFilter setDefaults];
        [darkenFilter setValue:[NSNumber numberWithFloat:2.5] forKey:@"inputPower"];
        
        _rastaLayer = [CALayer layer];
        _rastaLayer.backgroundColor = [[NSColor colorWithPatternImage:[NSImage imageNamed:@"LargeRastaPattern"]] CGColor];
        _rastaLayer.contentsScale = NSViewLayerContentsPlacementScaleProportionallyToFill;
        _rastaLayer.anchorPoint = CGPointMake(1.0, 0.0);
        _rastaLayer.autoresizingMask = kCALayerWidthSizable;
        _rastaLayer.frame = NSMakeRect(self.bounds.origin.x,
                                       self.bounds.origin.y,
                                       self.bounds.size.width,
                                       self.bounds.size.height);
        _rastaLayer.zPosition = 1.1;
        _rastaLayer.drawsAsynchronously = YES;
        _rastaLayer.opacity = 0.7;
        _rastaLayer.compositingFilter = [CIFilter filterWithName:@"CISourceAtopCompositing"];
        
        _aheadVibranceFxLayer = [CALayer layer];
        _aheadVibranceFxLayer.backgroundFilters = @[ darkenFilter, vibranceFilter ];
        _aheadVibranceFxLayer.anchorPoint = CGPointMake(0.0, 0.0);
        // FIXME: This looks weird - why 4?
        _aheadVibranceFxLayer.frame = CGRectMake(0.0, 0.0, self.bounds.size.width * 4, self.bounds.size.height);
        _aheadVibranceFxLayer.masksToBounds = NO;
        _aheadVibranceFxLayer.drawsAsynchronously = YES;
        _aheadVibranceFxLayer.zPosition = 1.0;
        
        _aheadVibranceFxLayerMask = [CAShapeLayer layer];
        NSRect rect = _aheadVibranceFxLayer.frame;
        _aheadVibranceFxLayerMask.fillRule = kCAFillRuleEvenOdd;
        NSBezierPath* path = [NSBezierPath bezierPath];
        [path appendBezierPathWithRect:rect];
        _aheadVibranceFxLayerMask.path = [NSBezierPath CGPathFromPath:path];
        _aheadVibranceFxLayer.mask = _aheadVibranceFxLayerMask;
        
        CIFilter* trailBloomFilter = [CIFilter filterWithName:@"CIBloom"];
        [trailBloomFilter setDefaults];
        [trailBloomFilter setValue:[NSNumber numberWithFloat:3.0] forKey:@"inputRadius"];
        [trailBloomFilter setValue:[NSNumber numberWithFloat:1.0] forKey:@"inputIntensity"];
        
        _trailBloomFxLayer = [CALayer layer];
        _trailBloomFxLayer.backgroundFilters = @[ trailBloomFilter ];
        _trailBloomFxLayer.anchorPoint = CGPointMake(1.0, 0.0);
        // FIXME: This looks weird - why 4?
        _trailBloomFxLayer.frame = CGRectMake(0.0, 0.0, self.bounds.size.width * 4, self.bounds.size.height);
        _trailBloomFxLayer.masksToBounds = NO;
        _trailBloomFxLayer.zPosition = 1.9;
        _trailBloomFxLayer.drawsAsynchronously = YES;
        _trailBloomFxLayer.name = @"TailBloomFxLayer";
        _trailBloomFxLayer.mask = [CAShapeLayer MaskLayerFromRect:_trailBloomFxLayer.frame];
    }
    return self;
}

- (void)viewDidMoveToSuperview
{
    [super viewDidMoveToSuperview];

    [self.layer addSublayer:_trailBloomFxLayer];

    [self.layer addSublayer:_aheadVibranceFxLayer];
    [self.layer addSublayer:_rastaLayer];
}



//- (void)updateHeadPosition:(CGFloat)head
//{
//    _headBloomFxLayer.position = CGPointMake(head, _headBloomFxLayer.position.y);
//    _headLayer.position = CGPointMake(head, _headLayer.position.y);
//    _aheadVibranceFxLayer.position = CGPointMake(head + (_headImageSize.width / 2.0f), 0.0);
//
//    _rastaLayer.frame = NSMakeRect(0.0, 0.0, floor(head), _rastaLayer.bounds.size.height);
//
//    _rastaLayer.position = CGPointMake(floor(head), 0.0);
//    _tailBloomFxLayer.position = CGPointMake(head - (_headImageSize.width / 2.0f), 0.0);
//}


- (void)setHead:(CGFloat)head
{
    _rastaLayer.frame = NSMakeRect(_rastaLayer.frame.origin.x,
                                   _rastaLayer.frame.origin.y,
                                   self.documentVisibleRect.size.width,
                                   _rastaLayer.frame.size.height);
    if (NSPointInRect(NSMakePoint(head, 1.0f), self.documentVisibleRect)) {
        _aheadVibranceFxLayer.position = CGPointMake(head + 0.0 - self.documentVisibleRect.origin.x, self.bounds.origin.y);
        _trailBloomFxLayer.position = CGPointMake((head + 4.0) - self.documentVisibleRect.origin.x, self.bounds.origin.y);
    } else {
        if (head < self.documentVisibleRect.origin.x) {
            _aheadVibranceFxLayer.position = CGPointMake(self.bounds.origin.x, self.documentVisibleRect.origin.y);
            _trailBloomFxLayer.position = CGPointMake(self.bounds.origin.x, self.documentVisibleRect.origin.y);
        } else {
            _aheadVibranceFxLayer.position = CGPointMake(self.documentVisibleRect.size.width, self.bounds.origin.y);
            _trailBloomFxLayer.position = CGPointMake(self.documentVisibleRect.size.width, self.bounds.origin.y);
        }
    }
}

- (void)resize
{
    _aheadVibranceFxLayer.bounds = CGRectMake(0.0f,
                                              0.0f,
                                              self.bounds.size.width,
                                              self.bounds.size.height);
    _trailBloomFxLayer.bounds = CGRectMake(0.0f,
                                              0.0f,
                                              self.bounds.size.width,
                                              self.bounds.size.height);
    // FIXME: We are redoing the mask layer cause all ways of resizing it
    // ended up with rather weird effects.
    _aheadVibranceFxLayer.mask = [CAShapeLayer MaskLayerFromRect:_aheadVibranceFxLayer.bounds];
    
    _trailBloomFxLayer.mask = [CAShapeLayer MaskLayerFromRect:_trailBloomFxLayer.bounds];
}

@end
