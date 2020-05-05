//
//  VisualSample.h
//  PlayEm
//
//  Created by Till Toenshoff on 19.04.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef struct {
//    double negativeMax;
//    double positiveMax;
    double negativeAverage;
    double positiveAverage;
} VisualPair;

@class LazySample;

@interface VisualSample : NSObject

@property (strong, nonatomic) LazySample* sample;
@property (readonly, nonatomic) size_t width;
@property (assign, nonatomic) double pixelPerSecond;

- (id)initWithSample:(LazySample*)sample pixelPerSecond:(double)pixelPerSecond tileWidth:(size_t)tileWidth;
- (NSData* _Nullable)visualsFromOrigin:(size_t)origin;
- (void)prepareVisualsFromOrigin:(size_t)origin width:(size_t)width window:(size_t)window total:(size_t)totalWidth callback:(void (^)(void))callback;

@end

NS_ASSUME_NONNULL_END
