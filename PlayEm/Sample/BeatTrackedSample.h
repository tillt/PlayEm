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
    BeatEvent* _Nullable currentEvent;
} BeatEventIterator;

typedef struct _BeatsParserContext BeatsParserContext;

@class EnergyDetector;
@class LazySample;

///
/// Tracks beats and tempo for a given sample.
///
/// Beat events can be enumerated using  a `BeatEventIterator`.
///
@interface BeatTrackedSample : NSObject

// FIXME: Allows for retrieval of beat events based on a screen origin - this is all too weird - feels like we should have something
// FIXME: inbetween there. Screen stuff shouldnt be of any concern here.

@property (assign, nonatomic) double framesPerPixel;
@property (strong, nonatomic) LazySample* sample;
// Beats as refined through the Mixx algorithm.
@property (strong, nonatomic) NSMutableDictionary* beats;
@property (strong, nonatomic) NSMutableDictionary* beatsPerPage;
// Beats as gathered from Aubio.
@property (strong, nonatomic) NSMutableData* coarseBeats;
@property (readonly, nonatomic) BOOL ready;
@property (readonly, nonatomic) size_t tileWidth;
@property (readonly, nonatomic) unsigned long long initialSilenceEndsAtFrame;
@property (readonly, nonatomic) unsigned long long trailingSilenceStartsAtFrame;
@property (strong, nonatomic) EnergyDetector* energy;


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
