//
//  NSImage+Resize.h
//  PlayEm
//
//  Created by Till Toenshoff on 3/29/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSImage (Resize)

+ (NSImage *)resizedImage:(NSImage*)image size:(NSSize)size;

@end

NS_ASSUME_NONNULL_END
