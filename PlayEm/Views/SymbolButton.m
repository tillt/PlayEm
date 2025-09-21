//
//  SymbolButton.m
//  PlayEm
//
//  Created by Till Toenshoff on 9/21/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import "SymbolButton.h"


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
        _imageView = [[NSImageView alloc] initWithFrame:NSInsetRect(self.bounds, 6.0, 2.0)];
        _imageView.autoresizingMask = NSViewHeightSizable | NSViewWidthSizable;
        [self addSubview:_imageView];
    }
    return self;
}

- (void)viewWillMoveToWindow:(NSWindow*)window
{
    NSTrackingArea* tracking = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                            options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingAssumeInside
                                                              owner:self
                                                           userInfo:nil];
    [self addTrackingArea:tracking];
    [self updateTrackingAreas];
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
    self.imageView.contentTintColor = self.highlighted ? [NSColor labelColor] : [NSColor secondaryLabelColor];
}

- (void)setHighlighted:(BOOL)highlighted
{
    [super setHighlighted:highlighted];
    [self updateColor];
}

- (void)setState:(NSControlStateValue)state
{
    _state = state;
    [self transitionImage];
}

- (void)mouseDown:(NSEvent *)event
{
    self.highlighted = YES;
}

- (void)mouseUp:(NSEvent *)event
{
    self.state = self.state == NSControlStateValueOff ? NSControlStateValueOn : NSControlStateValueOff;
    self.highlighted = NO;

    ActionMethodImplementation impl;
    impl = (ActionMethodImplementation)[self.target methodForSelector:self.action];
    impl(self.target, self.action, self);
}

- (void)transitionImage
{
    NSImage* imageWithConfig = [self currentSymbolImage];

    NSSymbolReplaceContentTransition* transition = [NSSymbolReplaceContentTransition replaceDownUpTransition];
    NSSymbolEffectOptions* options = [NSSymbolEffectOptions optionsWithSpeed:10.0];

    [self.imageView setSymbolImage:imageWithConfig
             withContentTransition:transition
                           options:options];
}

- (NSImage*)currentSymbolImage
{
    NSString* name = self.state == NSControlStateValueOn ? _alternateSymbolName : _symbolName;
    NSImage* image = [NSImage imageWithSystemSymbolName:name
                               accessibilityDescription:@""];
    NSImageSymbolConfiguration* config = [NSImageSymbolConfiguration configurationWithPointSize:100
                                                                                         weight:NSFontWeightRegular
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
