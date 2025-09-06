//
//  BloomyText.h
//  PlayEm
//
//  Created by Till Toenshoff on 9/6/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//
#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface BloomyText : NSView <CALayerDelegate>

@property (nonatomic, copy) NSString* text;
@property (nonatomic, strong) NSColor* lightTextColor;
@property (nonatomic, strong) NSColor* textColor;
@property (nonatomic, strong) NSFont* font;
@property (nonatomic, assign) CGFloat fontSize;

@end

NS_ASSUME_NONNULL_END
