//
//  TableCellView.m
//  PlayEm
//
//  Created by Till Toenshoff on 08.06.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import "TableCellView.h"

#import <Quartz/Quartz.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>

#import "CAShapeLayer+Path.h"
#import "Defaults.h"
#import "BeatEvent.h"


@interface TableCellView ()
@property (nonatomic, strong) NSTextField* tf;
@end

@implementation TableCellView
{
}

- (id)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        _tf = [[NSTextField alloc] initWithFrame:NSInsetRect(frameRect, 0.0, 5.0)];
        _tf.drawsBackground = NO;
        _tf.backgroundColor = [NSColor clearColor];
        _tf.editable = NO;
        _tf.font = [[Defaults sharedDefaults] smallFont];
        _tf.bordered = NO;
        _tf.alignment = NSTextAlignmentLeft;
        _tf.textColor = [[Defaults sharedDefaults] secondaryLabelColor];
        _tf.autoresizingMask = NSViewWidthSizable;
        _tf.cell.truncatesLastVisibleLine = YES;
        _tf.cell.lineBreakMode = NSLineBreakByTruncatingTail;
        self.textField = _tf;
        [self addSubview:_tf];
        //self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawOnSetNeedsDisplay;
    }
    return self;
}

- (void)setupWithFrame:(NSRect)frameRect
{
}

- (void)updatedStyle
{
    NSColor* color = nil;

    if (_extraState == kExtraStateActive || _extraState == kExtraStatePlaying) {
        color = [[Defaults sharedDefaults] lightFakeBeamColor];
    } else {
        switch (self.backgroundStyle) {
            case NSBackgroundStyleNormal:
                color = [[Defaults sharedDefaults] secondaryLabelColor];
                break;
            case NSBackgroundStyleEmphasized:
                color = [[Defaults sharedDefaults] lightFakeBeamColor];
                break;
            case NSBackgroundStyleRaised:
            case NSBackgroundStyleLowered:
            default:
                color = [NSColor linkColor];
        }
    }
    //_textLayer.foregroundColor = color.CGColor;
    self.textField.textColor = color;
}

- (void)setExtraState:(ExtraState)extraState
{
    _extraState = extraState;
    [self updatedStyle];
}

// FIXME: These are far too expensive -- no idea why that is.
- (void)beatEffect:(NSNotification*)notification
{
    const NSDictionary* dict = notification.object;
    const unsigned int style = [dict[kBeatNotificationKeyStyle] intValue];
    const float tempo = [dict[kBeatNotificationKeyTempo] floatValue];
    const float barDuration = 4.0f * 60.0f / tempo;
    
    if ((style & BeatEventStyleBar) == BeatEventStyleBar) {
        // For creating a discrete effect accross the timeline, a keyframe animation is the
        // right thing as it even allows us to animate strings.
        CAKeyframeAnimation* animation = [CAKeyframeAnimation animationWithKeyPath:@"foregroundColor"];
        animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
        
        //animation.fromValue = (id)[[[Defaults sharedDefaults] lightBeamColor] CGColor];
        //animation.toValue = (id)[[NSColor secondaryLabelColor] CGColor];
        animation.values = @[ (id)[[[Defaults sharedDefaults] lightFakeBeamColor] CGColor],
                              (id)[[NSColor secondaryLabelColor] CGColor] ];
        animation.fillMode = kCAFillModeBoth;
        [animation setValue:@"barSyncedColor" forKey:@"name"];
        animation.removedOnCompletion = NO;
        animation.repeatCount = 1;
        // We animate throughout an entire bar.
        animation.duration = barDuration;
        //[_textLayer addAnimation:animation forKey:@"barSynced"];
    }
}

- (void)setBackgroundStyle:(NSBackgroundStyle)backgroundStyle
{
    [super setBackgroundStyle:backgroundStyle];
    [self updatedStyle];
}

@end
