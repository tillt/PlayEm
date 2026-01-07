//
//  Defaults.h
//  PlayEm
//
//  Created by Till Toenshoff on 25.11.22.
//  Copyright © 2022 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

NS_ASSUME_NONNULL_BEGIN

@interface Defaults : NSObject

@property (strong, nonatomic) NSColor* lightBeamColor;
@property (strong, nonatomic) NSColor* lightFakeBeamColor;

@property (strong, nonatomic) NSColor* regularBeamColor;
@property (strong, nonatomic) NSColor* regularFakeBeamColor;

@property (strong, nonatomic) NSColor* fftColor;
@property (strong, nonatomic) NSColor* backColor;

@property (strong, nonatomic) NSColor* selectionBorderColor;

@property (strong, nonatomic) NSColor* barColor;
@property (strong, nonatomic) NSColor* beatColor;

@property (strong, nonatomic) NSColor* markerColor;

@property (strong, nonatomic) NSColor* secondaryLabelColor;
@property (strong, nonatomic) NSColor* tertiaryLabelColor;

@property (assign, nonatomic) CGFloat smallFontSize;
@property (assign, nonatomic) CGFloat normalFontSize;
@property (assign, nonatomic) CGFloat largeFontSize;
@property (assign, nonatomic) CGFloat bigFontSize;

@property (strong, nonatomic) NSFont* smallFont;
@property (strong, nonatomic) NSFont* normalFont;
@property (strong, nonatomic) NSFont* largeFont;
@property (strong, nonatomic) NSFont* bigFont;

+ (id)sharedDefaults;

@end

NS_ASSUME_NONNULL_END
