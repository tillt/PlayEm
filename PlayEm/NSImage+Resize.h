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

+ (NSImage* _Nullable)resizedImage:(NSImage* _Nullable)image size:(NSSize)size;
+ (NSImage* _Nullable)resizedImageWithData:(NSData* _Nullable)data size:(NSSize)target;

@end

NS_ASSUME_NONNULL_END
