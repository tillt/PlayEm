//
//  Defaults.m
//  PlayEm
//
//  Created by Till Toenshoff on 25.11.22.
//  Copyright © 2022 Till Toenshoff. All rights reserved.
//

#import "Defaults.h"

static const CGFloat kSmallFontSize = 11.0f;
static const CGFloat kNormalFontSize = 13.0f;
static const CGFloat kLargeFontSize = 17.0f;
static const CGFloat kBigFontSize = 24.0f;

@implementation Defaults

+ (id)sharedDefaults
{
    static Defaults *sharedMyDefaults = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedMyDefaults = [[self alloc] init];
    });
    return sharedMyDefaults;
}

- (id)init
{
    self = [super init];
    if (self) {
        _lightBeamColor = [NSColor colorWithRed:1.0f
                                          green:(CGFloat)0xE0 / 255.0f
                                           blue:(CGFloat)0x90 / 255.0f
                                          alpha:(CGFloat)1.0f];

        _lightFakeBeamColor = [NSColor colorWithRed:_lightBeamColor.redComponent
                                              green:_lightBeamColor.greenComponent
                                               blue:_lightBeamColor.blueComponent * 0.6
                                              alpha:_lightBeamColor.alphaComponent];

        _regularBeamColor = [NSColor colorWithRed:(CGFloat)0xB0 / 255.0
                                            green:(CGFloat)0x66 / 255.0
                                             blue:(CGFloat)0x14 / 255.0
                                            alpha:(CGFloat)1.0f];

        _regularFakeBeamColor = [NSColor colorWithRed:_regularBeamColor.redComponent * 1.2
                                                green:_regularBeamColor.greenComponent * 1.2
                                                 blue:_regularBeamColor.blueComponent
                                                alpha:_regularBeamColor.alphaComponent];

        _fftColor = [NSColor colorWithRed:1.0f
                                    green:(CGFloat)0xAF / 255.0f
                                     blue:(CGFloat)0x4F / 255.0f
                                    alpha:(CGFloat)1.0f];
        
        _beatColor = [NSColor colorWithRed:1.00f
                                     green:0.43f
                                      blue:0.03f
                                     alpha:0.08f];
        
        _markerColor = [NSColor colorWithRed:1.00f
                                       green:0.43f
                                        blue:0.03f
                                       alpha:0.80f];

        _barColor = [NSColor colorWithRed:1.00f
                                    green:0.43f
                                     blue:0.03f
                                    alpha:0.30f];

        _backColor = [NSColor colorWithRed:0.11764706
                                     green:0.11764706
                                      blue:0.11764706
                                     alpha:1.00f];
        
        _secondaryLabelColor = [NSColor colorWithRed:1.000
                                               green:1.000
                                                blue:1.000
                                               alpha:0.54901961];

        _tertiaryLabelColor = [NSColor colorWithRed:1.000
                                              green:1.000
                                               blue:1.000
                                              alpha:0.54901961];

        _selectionBorderColor = [NSColor colorWithRed:(CGFloat)0x50 / 255.0
                                                green:(CGFloat)0x36 / 255.0
                                                 blue:(CGFloat)0x14 / 255.0
                                                alpha:(CGFloat)1.0];
        
        
        _normalFont = [NSFont systemFontOfSize:kNormalFontSize];
        _smallFont = [NSFont systemFontOfSize:kSmallFontSize];
        _largeFont = [NSFont systemFontOfSize:kLargeFontSize];
        _bigFont = [NSFont systemFontOfSize:kBigFontSize];

    }
    return self;
}

@end
