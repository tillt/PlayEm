//
//  BeatTrackedSample.h
//  PlayEm
//
//  Created by Till Toenshoff on 06.08.23.
//  Copyright © 2023 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "BeatEvent.h"

#ifndef BeatTrackedSample_h
#define BeatTrackedSample_h

NS_ASSUME_NONNULL_BEGIN

typedef struct {
    size_t pageIndex;
    size_t eventIndex;
    const BeatEvent* _Nullable currentEvent;
} BeatEventIterator;

typedef struct _BeatsParserContext BeatsParserContext;

@class LazySample;

@interface BeatTrackedSample : NSObject

@property (assign, nonatomic) double framesPerPixel;
@property (strong, nonatomic) LazySample* sample;
@property (strong, nonatomic) NSMutableDictionary* beats;
@property (strong, nonatomic) NSMutableData* coarseBeats;
@property (readonly, nonatomic) BOOL ready;
@property (readonly, nonatomic) size_t tileWidth;
@property (readonly, nonatomic) unsigned long long initialSilenceEndsAtFrame;
@property (readonly, nonatomic) unsigned long long trailingSilenceStartsAtFrame;


- (void)abortWithCallback:(nonnull void (^)(void))block;

- (id)initWithSample:(LazySample*)sample framesPerPixel:(double)framesPerPixel;
- (NSData* _Nullable)beatsFromOrigin:(size_t)origin;

- (void)trackBeatsAsyncWithCallback:(void (^)(BOOL))callback;

- (unsigned long long)seekToFirstBeat:(nonnull BeatEventIterator*)iterator;
- (unsigned long long)seekToNextBeat:(nonnull BeatEventIterator*)iterator;
- (unsigned long long)seekToPreviousBeat:(nonnull BeatEventIterator*)iterator;

- (unsigned long long)frameForPreviousBeat:(nonnull BeatEventIterator*)iterator;

- (float)currentTempo:(nonnull BeatEventIterator*)iterator;
- (unsigned long long)currentEventFrame:(BeatEventIterator*)iterator;

+ (void)copyIteratorFromSource:(nonnull BeatEventIterator*)source destination:(nonnull BeatEventIterator*)destination;


@end

NS_ASSUME_NONNULL_END
#endif /* BeatTrackedSample_h */
