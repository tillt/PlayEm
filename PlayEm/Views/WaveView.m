//
//  WaveView.m
//  PlayEm
//
//  Created by Till Toenshoff on 16.08.23.
//  Copyright © 2023 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreImage/CoreImage.h>
#import "WaveView.h"
#import "CAShapeLayer+Path.h"
#import "NSBezierPath+CGPath.h"

@interface WaveView ()
- (void)updateHeadPosition;
@end

@interface WaveView () // Private

@property (strong, nonatomic) NSArray* trailBloomFxLayers;
@property (nonatomic, assign) BOOL followTime;
@property (nonatomic, assign) BOOL userMomentum;

@end

@implementation WaveView


- (void)viewDidMoveToSuperview
{
    [super viewDidMoveToSuperview];
    
    self.layer = [self makeBackingLayer];
    self.layer.masksToBounds = NO;

    _headLayer = [CALayer layer];
    
    NSImage* image = [NSImage imageNamed:@"CurrentTime"];
    image.resizingMode = NSImageResizingModeTile;
    
    CIFilter* clampFilter = [CIFilter filterWithName:@"CIAffineClamp"];
    [clampFilter setDefaults];

    //CGFloat scaleFactor = 1.15;
    CGFloat scaleFactor = 1.05;

    CGAffineTransform transform = CGAffineTransformScale(CGAffineTransformMakeTranslation(0.0, self.enclosingScrollView.bounds.size.height * -(scaleFactor - 1.0) / 2.0), 1.0, scaleFactor);
    [clampFilter setValue:[NSValue valueWithBytes:&transform objCType:@encode(CGAffineTransform)] forKey:@"inputTransform"];

    CIFilter* clampFilter2 = [CIFilter filterWithName:@"CIAffineClamp"];
    [clampFilter2 setDefaults];

    CIFilter* bloomFilter = [CIFilter filterWithName:@"CIBloom"];
    [bloomFilter setDefaults];
    [bloomFilter setValue: [NSNumber numberWithFloat:7.0] forKey: @"inputRadius"];
    [bloomFilter setValue: [NSNumber numberWithFloat:1.0] forKey: @"inputIntensity"];

    CIFilter* headFilter = [CIFilter filterWithName:@"CISourceAtopCompositing"];
    [headFilter setDefaults];

    CGFloat height = self.enclosingScrollView.bounds.size.height;
    
    _headLayer.contents = image;
    _headImageSize = image.size;
    _headLayer.anchorPoint = CGPointMake(0.5, 0.0);
    _headLayer.frame = CGRectMake(0.0, 0.0, _headImageSize.width, height);
    _headLayer.compositingFilter = [CIFilter filterWithName:@"CISourceAtopCompositing"];
    _headLayer.zPosition = 1.1;
    _headLayer.name = @"HeadLayer";

    _headBloomFxLayer = [CALayer layer];
    _headBloomFxLayer.backgroundFilters = @[ clampFilter, bloomFilter ];
    _headBloomFxLayer.anchorPoint = CGPointMake(0.5, 0.0);
    _headBloomFxLayer.frame = CGRectMake(0.0, 0.0, 5.0, height);
    _headBloomFxLayer.masksToBounds = NO;
    _headBloomFxLayer.zPosition = 1.9;
    _headBloomFxLayer.name = @"HeadBloomFxLayer";
    _headBloomFxLayer.mask = [CAShapeLayer MaskLayerFromRect:_headBloomFxLayer.frame];

    [self.layer addSublayer:_headLayer];
    [self.layer addSublayer:_headBloomFxLayer];
    
    _hudLayer = [CALayer layer];
    _hudLayer.anchorPoint = CGPointMake(0.5, 0.0);
    _hudLayer.frame = CGRectMake(0.0, 0.0, _headImageSize.width, height);
    //_hudLayer.compositingFilter = [CIFilter filterWithName:@"CISourceAtopCompositing"];
    _hudLayer.zPosition = 2.0;
    _hudLayer.name = @"HUDLayer";

    const unsigned int trailingBloomLayerCount = 3;
    NSMutableArray* layers = [NSMutableArray array];
    for (int i = 0; i < trailingBloomLayerCount; i++) {
        CIFilter* bloom = [CIFilter filterWithName:@"CIBloom"];
        [bloom setDefaults];
        [bloom setValue: [NSNumber numberWithFloat:(float)(2 + trailingBloomLayerCount - i) * 1.0] forKey: @"inputRadius"];
        [bloom setValue: [NSNumber numberWithFloat:1.0] forKey: @"inputIntensity"];

        CALayer* layer = [CALayer layer];
        layer.backgroundFilters = @[ bloom ];
        layer.anchorPoint = CGPointMake(1.0, 0.0);
        layer.frame = CGRectMake(0.0, 0.0, floor(_headImageSize.width / (2 * trailingBloomLayerCount)), height);
        layer.masksToBounds = NO;
        layer.zPosition = 1.99;
        layer.name = [NSString stringWithFormat:@"TrailBloomFxLayer%d", i+1];
        layer.mask = [CAShapeLayer MaskLayerFromRect:layer.frame];
        [layers addObject:layer];

        [self.layer addSublayer:layer];
    }
    _trailBloomFxLayers = [layers copy];

    _followTime = YES;
    _userMomentum = NO;
}

- (void)dealloc
{
}

- (void)rightMouseDown:(NSEvent*)event
{
    _followTime = YES;
    [self updateScrollingState];
}

- (BOOL)wantsLayer
{
    return YES;
}

- (CALayer*)makeBackingLayer
{
    CALayer* layer = [CALayer layer];
    return layer;
}

- (void)invalidateTiles
{
    for (NSView* view in [self subviews]) {
        [view.layer setNeedsDisplay];
        [view.layer.sublayers[0] setNeedsDisplay];
    }
}

- (void)setFrames:(unsigned long long)frames
{
    if (_frames == frames) {
        return;
    }
    _frames = frames;
    [self invalidateTiles];
    self.currentFrame = 0;
}

- (void)layout
{
    [super layout];
    [self updateHeadPosition];
}

- (void)updateHeadPosition
{
    if (_frames == 0.0) {
        return;
    }
    
    _head = ( _currentFrame * self.bounds.size.width) / _frames;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    _headLayer.position = CGPointMake(_head, 0.0);
    _headBloomFxLayer.position = CGPointMake(_head, 0.0);
    
    CGFloat x = 0;
    CGFloat offset = 0.0;
    for (CALayer* layer in _trailBloomFxLayers) {
        layer.position = CGPointMake((_head + offset) - x, 0.0);
        x += layer.frame.size.width;
    }

    [_headDelegate updatedHeadPosition];

    [CATransaction commit];
}

- (void)setCurrentFrame:(unsigned long long)frame
{
    if (_currentFrame == frame) {
        return;
    }
    if (_frames == 0.0) {
        return;
    }
    _currentFrame = frame;
    
    [self updateScrollingState];
}

- (void)updateScrollingState
{
    CGFloat head = (_currentFrame * self.bounds.size.width) / _frames;
   
    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    if (_followTime) {
        [self scrollRectToVisible:CGRectMake(floor(head - (self.enclosingScrollView.bounds.size.width / 2.0)),
                                             0.0,
                                             self.enclosingScrollView.bounds.size.width,
                                             self.bounds.size.height)];
    } else {
        // If the user has just requested some scrolling, do not interfere but wait
        // as long as that state is up.
        if (!_userMomentum) {
            // If the head came back into the middle of the screen, snap back to following
            // time with the scrollview.
            const CGFloat delta = 1.0f;
            CGFloat visibleCenter = self.enclosingScrollView.documentVisibleRect.origin.x + (self.enclosingScrollView.documentVisibleRect.size.width / 2.0f);
            if (visibleCenter - delta <= head && visibleCenter + delta >= head) {
                _followTime = YES;
            }
        }
    }
    [self updateHeadPosition];
    [CATransaction commit];
}

- (void)userInitiatedScrolling
{
    _userMomentum = YES;
    _followTime = NO;
}

- (void)userEndsScrolling
{
    _userMomentum = NO;
}

@end

