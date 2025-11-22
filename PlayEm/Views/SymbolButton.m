//
//  SymbolButton.m
//  PlayEm
//
//  Created by Till Toenshoff on 9/21/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import "SymbolButton.h"

const static double transitionSpeedFactor = 10.0;

typedef void (*ActionMethodImplementation)(id, SEL, id);

@interface SymbolButton ()
{
}

@property (strong, nonatomic) NSImageView* imageView;
@property (assign, nonatomic) SEL userAction;

@end

@implementation SymbolButton

- (nonnull instancetype)initWithFrame:(CGRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        self.autoresizingMask = NSViewHeightSizable | NSViewWidthSizable;

        _state = NSControlStateValueOff;
        _imageView = [[NSImageView alloc] initWithFrame:NSInsetRect(self.bounds, 4.0, 4.0)];
        _imageView.autoresizingMask = NSViewHeightSizable | NSViewWidthSizable | NSViewMaxXMargin | NSViewMaxYMargin | NSViewMinYMargin| NSViewMinXMargin;
        [self addSubview:_imageView];
    }
    return self;
}

- (void)viewWillMoveToWindow:(NSWindow*)window
{
    [self addTrackingRect:self.bounds owner:self userData:NULL assumeInside:NO];
}

- (void)mouseEntered:(NSEvent *)event
{
}

- (void)mouseExited:(NSEvent *)event
{
    self.highlighted = NO;
}

- (void)updateColor
{
    if (self.enabled == NO) {
        self.imageView.contentTintColor = [NSColor disabledControlTextColor];
    } else {
        self.imageView.contentTintColor = self.highlighted ? [NSColor labelColor] : [NSColor secondaryLabelColor];
    }
}

- (void)setHighlighted:(BOOL)highlighted
{
    [super setHighlighted:highlighted];
    [self updateColor];
}

- (void)setEnabled:(BOOL)enabled
{
    [super setEnabled:enabled];
    [self updateColor];
}

- (void)setState:(NSControlStateValue)state
{
    _state = state;
    [self transitionImage];
}

- (void)mouseDown:(NSEvent *)event
{
    if (self.enabled == NO) {
        return;
    }
    self.highlighted = YES;
}

// FIXME: This doesnt work as regular buttons do. We need to assert that when the user clicks and drags outside the button, the action gets canceled.
- (void)mouseUp:(NSEvent *)event
{
    if (self.enabled == NO) {
        return;
    }
    if (event.type == NSEventTypeLeftMouseUp) {
        NSPoint pt = [self convertPoint:[event locationInWindow] fromView:nil];
        if (NSPointInRect(pt, self.bounds)) {
            // Flip state.
            self.state = self.state == NSControlStateValueOff ? NSControlStateValueOn : NSControlStateValueOff;

            // Call action.
            if (self.target) {
                ActionMethodImplementation impl;
                impl = (ActionMethodImplementation)[self.target methodForSelector:self.action];
                impl(self.target, self.action, self);
            }
        }
    }
    self.highlighted = NO;
}

- (void)transitionImage
{
    NSImage* imageWithConfig = [self currentSymbolImage];

    NSSymbolReplaceContentTransition* transition = [NSSymbolReplaceContentTransition replaceDownUpTransition];
    NSSymbolEffectOptions* options = [NSSymbolEffectOptions optionsWithSpeed:transitionSpeedFactor];

    [self.imageView setSymbolImage:imageWithConfig
             withContentTransition:transition
                           options:options];
}

- (NSImage*)currentSymbolImage
{
    NSString* name = self.state == NSControlStateValueOn ? _alternateSymbolName : _symbolName;
    NSImage* image = [NSImage imageWithSystemSymbolName:name
                               accessibilityDescription:@""];
    NSImageSymbolConfiguration* config = [NSImageSymbolConfiguration configurationWithPointSize:self.frame.size.height
                                                                                         weight:NSFontWeightBold
                                                                                          scale:NSImageSymbolScaleLarge];
    NSImage* imageWithConfig = [image imageWithSymbolConfiguration:config];
    return imageWithConfig;
}

- (void)setSymbolName:(NSString*)name
{
    if ([name isEqualToString:_symbolName]) {
        return;
    }
    _symbolName = name;
    self.imageView.image = [self currentSymbolImage];
}

- (void)setAlternateSymbolName:(NSString *)name
{
    if ([name isEqualToString:_alternateSymbolName]) {
        return;
    }
    _alternateSymbolName = name;
    self.imageView.image = [self currentSymbolImage];
}

@end
