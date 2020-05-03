//
//  ProgressView.m
//  PlayEm
//
//  Created by Till Toenshoff on 28.12.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import "ProgressView.h"

#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

@interface ProgressView ()

@property (nonatomic, strong) NSImage* normalLeft;
@property (nonatomic, strong) NSImage* normalMiddle;
@property (nonatomic, strong) NSImage* normalRight;

@property (nonatomic, strong) NSImage* activeLeft;
@property (nonatomic, strong) NSImage* activeMiddle;
@property (nonatomic, strong) NSImage* activeRight;

@property (nonatomic, strong) CALayer* thumbLayer;
@property (nonatomic, strong) CALayer* sparkleLayer;
@property (nonatomic, strong) CALayer* sparkleLayer2;

@end


@implementation ProgressView

- (void)awakeFromNib
{
    [super awakeFromNib];

    _max = 1.0;
    _current = 0.0;

    [self addTrackingRect:self.bounds owner:self userData:nil assumeInside:NO];

    self.normalLeft = [NSImage imageNamed:@"ProgressNormalLeft"];
    self.normalRight = [NSImage imageNamed:@"ProgressNormalRight"];
    self.normalMiddle = [NSImage imageNamed:@"ProgressNormalMiddle"];
    self.activeLeft = [NSImage imageNamed:@"ProgressActiveLeft"];
    self.activeRight = [NSImage imageNamed:@"ProgressActiveRight"];
    self.activeMiddle = [NSImage imageNamed:@"ProgressActiveMiddle"];

    self.wantsLayer = YES;
    self.layer = [self makeBackingLayer];
    self.layer.masksToBounds = NO;

    _sparkleLayer = [CALayer layer];
    NSImage* image = [NSImage imageNamed:@"Sparkle"];
    _sparkleLayer.contents = image;
    _sparkleLayer.opacity = 0.0f;
    _sparkleLayer.frame = CGRectMake(8.0f - (image.size.width / 2.0f), 6.0f - (image.size.height / 2.0f), image.size.width, image.size.height);
    _sparkleLayer.zPosition = 1.0;
    [self.layer addSublayer:self.sparkleLayer];

    _sparkleLayer2 = [CALayer layer];
    image = [NSImage imageNamed:@"Sparkle"];
    _sparkleLayer2.contents = image;
    _sparkleLayer2.opacity = 0.0f;
    _sparkleLayer2.frame = CGRectMake(8.0f - (image.size.width / 2.0f), 6.0f - (image.size.height / 2.0f), image.size.width, image.size.height);
    _sparkleLayer2.zPosition = 1.0;
    [self.layer addSublayer:self.sparkleLayer2];

    _thumbLayer = [CALayer layer];
    image = [NSImage imageNamed:@"ProgressThumb"];
    _thumbLayer.contents = image;
    _thumbLayer.opacity = 0.0f;
    _thumbLayer.frame = CGRectMake(8.0f - (image.size.width / 2.0f), 6.0f - (image.size.height / 2.0f), image.size.width, image.size.height);
    _thumbLayer.zPosition = 1.0;
    [self.layer addSublayer:self.thumbLayer];
}

- (void)mouseEntered:(NSEvent *)event
{
    _sparkleLayer.opacity = 1.0f;
    _thumbLayer.opacity = 1.0f;
    _thumbLayer.transform = CATransform3DMakeScale(1.1f, 1.1f, 1.0f);
    _sparkleLayer.transform = CATransform3DRotate(_thumbLayer.transform, (181.0f * M_PI / 180), 0.0, 0.0, 1.0f);
    _sparkleLayer2.transform = CATransform3DRotate(_thumbLayer.transform, (71.0f * M_PI / 180), 0.0, 0.0, 1.0f);
    
    CABasicAnimation* rotationAnimation;
    rotationAnimation = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    rotationAnimation.toValue = [NSNumber numberWithFloat: M_PI * 2.0];
    rotationAnimation.duration = 42.0f;
    rotationAnimation.cumulative = YES;
    rotationAnimation.repeatCount = HUGE_VALF;
    [_sparkleLayer addAnimation:rotationAnimation forKey:@"rotationAnimation"];

    rotationAnimation = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    rotationAnimation.toValue = [NSNumber numberWithFloat: M_PI * 2.0];
    rotationAnimation.duration = 42.0f;
    rotationAnimation.cumulative = YES;
    rotationAnimation.repeatCount = HUGE_VALF;
    rotationAnimation.duration = 18.0f;
    [_sparkleLayer2 addAnimation:rotationAnimation forKey:@"rotationAnimation"];

    CABasicAnimation* fadeAnimation;
    fadeAnimation = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fadeAnimation.fromValue = @( 1.0f );
    fadeAnimation.toValue = @( 0.01f );
    fadeAnimation.duration = 1.33f;
    fadeAnimation.cumulative = YES;
    fadeAnimation.autoreverses = NO;
    fadeAnimation.repeatCount = HUGE_VALF;
    fadeAnimation.fillMode = kCAFillModeBoth;
    [_sparkleLayer addAnimation:fadeAnimation forKey:@"fadeAnimation"];

    fadeAnimation = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fadeAnimation.cumulative = YES;
    fadeAnimation.autoreverses = NO;
    fadeAnimation.repeatCount = HUGE_VALF;
    fadeAnimation.fromValue = @( 0.8f );
    fadeAnimation.toValue = @( 0.01f );
    fadeAnimation.duration = 2.12f;
    [_sparkleLayer2 addAnimation:fadeAnimation forKey:@"fadeAnimation"];
}

- (void)mouseExited:(NSEvent *)event
{
    [_sparkleLayer removeAllAnimations];
    [_sparkleLayer2 removeAllAnimations];
    [_thumbLayer removeAllAnimations];
    _sparkleLayer.opacity = 0.0f;
    _sparkleLayer2.opacity = 0.0f;
    _thumbLayer.opacity = 0.0f;
    _thumbLayer.transform = CATransform3DIdentity;
    _sparkleLayer.transform = CATransform3DIdentity;
    _sparkleLayer2.transform = CATransform3DIdentity;
}

- (void)mouseDown:(NSEvent *)event
{
    NSPoint locationInWindow = [event locationInWindow];
    NSPoint location = [self convertPoint:locationInWindow fromView:nil];
    if (NSPointInRect(location, self.bounds)) {
        unsigned long long seekTo = (_max / self.frame.size.width) * location.x;
        NSLog(@"mouse down in progress view %f:%f -- seeking to %lld\n", location.x, location.y, seekTo);
        [_delegate progressSeekTo:seekTo];
    }
}

- (void)mouseDragged:(NSEvent *)event
{
    NSPoint locationInWindow = [event locationInWindow];
    NSPoint location = [self convertPoint:locationInWindow fromView:nil];
    if (NSPointInRect(location, self.bounds)) {
        unsigned long long seekTo = (_max / self.frame.size.width) * location.x;
        NSLog(@"mouse dragged in progress view %f:%f -- seeking to %lld\n", location.x, location.y, seekTo);
        [_delegate progressSeekTo:seekTo];
    }
}

- (CGFloat)thumbXWithFrame:(unsigned long long)frame
{
    return 4.0f + (((self.bounds.size.width - 8.0f) / _max) * frame);
}

- (void)drawRect:(NSRect)dirtyRect
{
    [super drawRect:dirtyRect];
    NSDrawThreePartImage(self.bounds, self.normalLeft, self.normalMiddle, self.normalRight, NO, NSCompositingOperationSourceOver, 1.0f, NO);
    NSRect a = NSMakeRect(self.bounds.origin.x, self.bounds.origin.y, [self thumbXWithFrame:_current] + 4.0f, self.bounds.size.height);
    NSDrawThreePartImage(a, self.activeLeft, self.activeMiddle, self.activeRight, NO, NSCompositingOperationSourceOver, MIN(1.0f, _current), NO);
}

- (void)setMax:(unsigned long long)max
{
    if (max == _max) {
        return;
    }
    _max = max;
    [self setNeedsDisplay:YES];
}

- (void)setCurrent:(unsigned long long)current
{
    if (current == _current) {
        return;
    }
    _current = current;
    [CATransaction begin];
    [CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
    _sparkleLayer2.position = CGPointMake([self thumbXWithFrame:current], _sparkleLayer.position.y);
    _sparkleLayer.position = CGPointMake([self thumbXWithFrame:current], _sparkleLayer.position.y);
    _thumbLayer.position = CGPointMake([self thumbXWithFrame:current], _thumbLayer.position.y);
    [CATransaction commit];
    [self setNeedsDisplay:YES];
}

@end
