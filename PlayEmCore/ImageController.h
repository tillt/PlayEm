//
//  ImageController.h
//  PlayEm
//
//  Created by Till Toenshoff on 12/21/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ImageController : NSObject

+ (instancetype)shared;

- (void)imageForData:(NSData*)data
                 key:(NSString*)key
                size:(CGFloat)size
          completion:(void(^)(NSImage* imgage))completion;

- (void)clearCache;
- (void)resolveDataForURL:(NSURL*)url callback:(void (^)(NSData*))callback;

@end
NS_ASSUME_NONNULL_END
