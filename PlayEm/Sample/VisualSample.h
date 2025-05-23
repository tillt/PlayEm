//
//  VisualSample.h
//  PlayEm
//
//  Created by Till Toenshoff on 19.04.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class LazySample;

@interface VisualSample : NSObject

@property (strong, nonatomic) LazySample* sample;
@property (readonly, nonatomic) size_t width;
@property (assign, nonatomic) double pixelPerSecond;

- (id)initWithSample:(LazySample*)sample pixelPerSecond:(double)pixelPerSecond tileWidth:(size_t)tileWidth;
- (id)initWithSample:(LazySample*)sample pixelPerSecond:(double)pixelPerSecond tileWidth:(size_t)tileWidth reducedWidth:(size_t)reducedWidth;

/// Get a visual data blob starting at a specific origin, if available.
- (NSData* _Nullable)visualsFromOrigin:(size_t)origin;
/// Calculate visual sample data starting from origin,
- (void)prepareVisualsFromOrigin:(size_t)origin width:(size_t)width window:(size_t)window total:(size_t)totalWidth callback:(void (^)(void))callback;
- (double)framesPerPixel;

@end

NS_ASSUME_NONNULL_END
