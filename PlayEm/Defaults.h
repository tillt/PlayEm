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

+ (id)sharedDefaults;

@end

NS_ASSUME_NONNULL_END
