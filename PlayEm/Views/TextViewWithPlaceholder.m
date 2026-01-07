//
//  TextViewWithPlaceholder.m
//  PlayEm
//
//  Created by Till Toenshoff on 01.03.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import "TextViewWithPlaceholder.h"

@implementation TextViewWithPlaceholder

- (id)init
{
    self = [super init];
    if (self) {
    }
    return self;
}

- (BOOL)becomeFirstResponder
{
    [self setNeedsDisplay:YES];
    return [super becomeFirstResponder];
}

- (void)drawRect:(NSRect)dirtyRect
{
    [super drawRect:dirtyRect];
    if ([[self string] isEqualToString:@""] && self != [[self window] firstResponder]) {
        [_placeholderAttributedString drawAtPoint:self.frame.origin];
    }
}

- (BOOL)resignFirstResponder
{
    [self setNeedsDisplay:YES];
    return [super resignFirstResponder];
}

@end
