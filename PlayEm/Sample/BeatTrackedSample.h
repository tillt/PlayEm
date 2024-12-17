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

typedef enum : NSUInteger {
    BeatEventStyleBeat  = 0x01,
    BeatEventStyleBar   = 0x02,
    BeatEventStyleFound = 0x04,
} BeatEventStyle;

typedef struct {
    BeatEventStyle      style;
    unsigned long long  frame;
    double              bpm;
} BeatEvent;

typedef struct {
    size_t pageIndex;
    size_t eventIndex;
    const BeatEvent* _Nullable currentEvent;
} BeatEventIterator;

typedef struct {
    unsigned long long firstBeatFrame;
    double beatLength;
} BeatConstRegion;

typedef struct _BeatsParserContext BeatsParserContext;

@class LazySample;

@interface BeatTrackedSample : NSObject

@property (assign, nonatomic) double framesPerPixel;
@property (strong, nonatomic) LazySample* sample;
@property (strong, nonatomic) NSMutableDictionary* beats;
@property (readonly, nonatomic) BOOL ready;

- (void)abortWithCallback:(nonnull void (^)(void))block;

- (id)initWithSample:(LazySample*)sample framesPerPixel:(double)framesPerPixel;
- (NSData* _Nullable)beatsFromOrigin:(size_t)origin;

- (void)trackBeatsAsyncWithCallback:(void (^)(BOOL))callback;

- (unsigned long long)frameForFirstBar:(nonnull BeatEventIterator*)iterator;
- (unsigned long long)frameForNextBar:(nonnull BeatEventIterator*)iterator;

//- (unsigned long long)framesPerBeat:(float)tempo;

- (float)currentTempo:(nonnull BeatEventIterator*)iterator;

@end

NS_ASSUME_NONNULL_END
#endif /* BeatTrackedSample_h */
