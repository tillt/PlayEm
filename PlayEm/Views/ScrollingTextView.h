//
//  ScrollingTextView.h
//  PlayEm
//
//  Created by Till Toenshoff on 14.11.22.
//  Copyright © 2022 Till Toenshoff. All rights reserved.
//
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

@interface ScrollingTextView : NSView <CALayerDelegate, CAAnimationDelegate>

@property (nonatomic, copy) NSString* text;
@property (nonatomic, strong) NSColor* textColor;
@property (nonatomic, strong) NSFont* font;

@end
