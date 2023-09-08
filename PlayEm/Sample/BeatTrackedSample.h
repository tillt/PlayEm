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

typedef struct {
    size_t pageIndex;
    size_t eventIndex;
    const BeatEvent* currentEvent;
} BeatEventIterator;

typedef struct _BeatsParserContext BeatsParserContext;

@class LazySample;

@interface BeatTrackedSample : NSObject

@property (assign, nonatomic) double framesPerPixel;
@property (strong, nonatomic) LazySample* sample;
@property (strong, nonatomic) NSMutableDictionary* beats;
@property (readonly, nonatomic) BOOL isReady;

- (id)initWithSample:(LazySample*)sample framesPerPixel:(double)framesPerPixel;
- (NSData* _Nullable)beatsFromOrigin:(size_t)origin;

- (void)trackBeatsAsyncWithCallback:(nonnull void (^)(void))callback;

- (float)tempo;

- (unsigned long long)firstBarAtFrame:(nonnull BeatEventIterator*)iterator;
- (unsigned long long)nextBarAtFrame:(nonnull BeatEventIterator*)iterator;

- (float)currentTempo:(nonnull BeatEventIterator*)iterator;

@end

NS_ASSUME_NONNULL_END
#endif /* BeatTrackedSample_h */
