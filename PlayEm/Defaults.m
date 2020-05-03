//
//  Defaults.m
//  PlayEm
//
//  Created by Till Toenshoff on 25.11.22.
//  Copyright © 2022 Till Toenshoff. All rights reserved.
//

#import "Defaults.h"

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
                                       green:(CGFloat)0xe0 / 255.0f
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

        _backColor = [NSColor controlBackgroundColor];
        
        _selectionBorderColor = [NSColor colorWithRed:(CGFloat)0x50 / 255.0
                         green:(CGFloat)0x36 / 255.0
                          blue:(CGFloat)0x14 / 255.0
                         alpha:(CGFloat)1.0];

    }
    return self;
}

@end
