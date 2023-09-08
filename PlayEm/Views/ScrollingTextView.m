//
//  ScrollingTextView.m
//  PlayEm
//
//  Created by Till Toenshoff on 14.11.22.
//  Copyright © 2022 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>

#import "ScrollingTextView.h"

@interface ScrollingTextView()

@property (nonatomic, strong) CATextLayer* first;
@property (nonatomic, strong) CATextLayer* second;
@property (nonatomic, assign) CGFloat stringWidth;
@property (nonatomic, strong, readonly) NSDictionary* attributes;

@end

@implementation ScrollingTextView

static const double kSpaceInRepeat = 30.0;
static const double kScrollSpeed = 1.0 / 24.0;

- (id)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.clipsToBounds = YES;
        self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;
        
        _first = [CATextLayer layer];
        _first.anchorPoint = CGPointMake(0.0, 0.0);
        _first.frame = self.bounds;
        _first.allowsEdgeAntialiasing = YES;
        [self.layer addSublayer:_first];
        
        _second = [[CATextLayer alloc] init];
        _second.anchorPoint = CGPointMake(0.0, 0.0);
        _second.frame = self.bounds;
        _second.allowsEdgeAntialiasing = YES;
        [self.layer addSublayer:_second];
        
        _font = [NSFont systemFontOfSize:13.0];
    }
    return self;
}

- (void)viewDidMoveToSuperview
{
    [super viewDidMoveToSuperview];
}

- (void)dealloc
{
}

- (void)setText:(NSString *)text
{
    if ([_text isEqualToString:text]) {
        return;
    }
    _text = text;
    
    [self setNeedsDisplay:YES];
}

- (NSDictionary*)attributes
{
    return @{ NSForegroundColorAttributeName:_textColor,
              NSFontAttributeName: _font    };
}

- (BOOL)canDrawSubviewsIntoLayer
{
    return NO;
}

- (BOOL)wantsUpdateLayer
{
    return YES;
}

- (void)setTextColor:(NSColor*)color
{
    if (color == _textColor) {
        return;
    }
    _textColor = color;
}

- (void)animationDidStop:(CAAnimation *)animation finished:(BOOL)finished
{
    if (finished) {
        [self setNeedsDisplay:YES];
    }
}

- (void)addAnimation:(CATextLayer*)layer
{
    CGFloat width = ceil([(NSAttributedString*)layer.string size].width);

    [CATransaction begin];

    CABasicAnimation* animation = [CABasicAnimation animationWithKeyPath:@"position"];
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    animation.fromValue = [NSValue valueWithPoint:layer.position];
    animation.toValue = [NSValue valueWithPoint:CGPointMake(0 - (width + kSpaceInRepeat), 0.0)];
    animation.duration = (width + kSpaceInRepeat + layer.position.x) * kScrollSpeed;
    animation.fillMode = kCAFillModeBoth;
    animation.removedOnCompletion = NO;
    animation.delegate = self;

    [layer addAnimation:animation forKey:@"ScrollAnimation"];
}

- (void)updateLayer
{
    [_first removeAnimationForKey:@"ScrollAnimation"];
    [_second removeAnimationForKey:@"ScrollAnimation"];
    
    if (_text == nil || _text.length == 0) {
        return;
    }
    
    NSAttributedString* attributedString = [[NSAttributedString alloc] initWithString:_text
                                                                           attributes:self.attributes];

    _first.string = attributedString;
    _second.string = attributedString;

    CGFloat width = ceil([attributedString size].width);

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _first.frame = CGRectMake(0.0, 0.0, width, self.frame.size.height);
    _first.position = CGPointZero;
    _second.frame = CGRectMake(0.0, 0.0, width, self.frame.size.height);
    _second.position = CGPointMake(MAX(width + kSpaceInRepeat, self.frame.size.width), 0.0f);
    [CATransaction commit];
    
    if (width > self.frame.size.width) {
        [self addAnimation:_first];
        [self addAnimation:_second];
    }
}

@end
