//
//  NSBezierPath+CGPath.h
//  PlayEm
//
//  Created by Till Toenshoff on 16.10.22.
//  Copyright © 2022 Till Toenshoff. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSBezierPath (CGPath)

+ (CGMutablePathRef)CGPathFromPath:(NSBezierPath *)path;

@end

NS_ASSUME_NONNULL_END
