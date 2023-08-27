//
//  BeatTrackedSample.h
//  PlayEm
//
//  Created by Till Toenshoff on 06.08.23.
//  Copyright © 2023 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>

#ifndef BeatTrackedSample_h
#define BeatTrackedSample_h

NS_ASSUME_NONNULL_BEGIN

//typedef struct {
//    double negativeAverage;
//    double positiveAverage;
//} VisualPair;

typedef struct {
    unsigned long long frame;
    float bpm;
    float confidence;
} BeatEvent;

@class LazySample;

@interface BeatTrackedSample : NSObject

@property (assign, nonatomic) double framesPerPixel;
@property (strong, nonatomic) LazySample* sample;
@property (strong, nonatomic) NSMutableData* beats;

- (id)initWithSample:(LazySample*)sample framesPerPixel:(double)framesPerPixel;
- (NSData* _Nullable)beatsFromOrigin:(size_t)origin;
- (void)prepareBeatsFromOrigin:(size_t)origin callback:(void (^)(void))callback;

- (float)tempoForOrigin:(size_t)origin;

- (void)trackBeatsAsync:(size_t)totalWidth callback:(nonnull void (^)(void))callback;

@end

NS_ASSUME_NONNULL_END
#endif /* BeatTrackedSample_h */
