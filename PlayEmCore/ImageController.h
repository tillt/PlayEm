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

/// Returns a resized thumbnail for the given image data, delivered asynchronously.
///
/// Uses the supplied `key` and `size` to cache thumbnails in-memory. The resize work is performed off the main thread; the `completion` block is always invoked on the main queue with the resulting `NSImage` (or `nil` on failure).
///
/// - Parameters:
///   - data: Raw image bytes to decode and scale.
///   - key: Cache key identifying the source (e.g. track id or URL).
///   - size: Target square edge length in points for the thumbnail.
///   - completion: Invoked on the main queue with the cached or newly generated image.
- (void)imageForData:(NSData*)data key:(NSString*)key size:(CGFloat)size completion:(void (^)(NSImage* imgage))completion;

/// Clears all cached thumbnails from the in-memory cache.
- (void)clearCache;

/// Asynchronously downloads data from the given URL and returns it on the main queue.
///
/// - Parameters:
///   - url: Remote resource URL to fetch.
///   - callback: Invoked on the main queue with the downloaded data (or nil on failure).
- (void)resolveDataForURL:(NSURL*)url callback:(void (^)(NSData*))callback;

@end
NS_ASSUME_NONNULL_END
