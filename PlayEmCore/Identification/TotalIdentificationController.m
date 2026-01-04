//
//  TotalIdentificationController.m
//  PlayEm
//
//  Created by Till Toenshoff on 12/26/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import "TotalIdentificationController+Private.h"

#import "../Sample/LazySample.h"
#import "../Metadata/TimedMediaMetaData.h"
#import <float.h>

NS_ASSUME_NONNULL_BEGIN

// Test-only setter to inject raw hits for refinement without exposing the property publicly.
#ifdef DEBUG
@interface TotalIdentificationController (TestingAccess)
- (void)testing_setIdentifieds:(NSArray<TimedMediaMetaData *> *)hits;
- (NSDictionary<NSString *, NSNumber *> *)testing_metrics;
@end

@implementation TotalIdentificationController (TestingAccess)
- (void)testing_setIdentifieds:(NSArray<TimedMediaMetaData *> *)hits
{
    self.identifieds = [hits mutableCopy];
}

- (NSDictionary<NSString *, NSNumber *> *)testing_metrics
{
    double avgLatency = 0.0;
    if (self.matchResponseCount > 0) {
        avgLatency = self.responseLatencySum / (double)self.matchResponseCount;
    }
    double minLatency = self.responseLatencyMin == DBL_MAX ? 0.0 : self.responseLatencyMin;
    return @{
        @"match_requests": @(self.matchRequestCount),
        @"match_responses": @(self.matchResponseCount),
        @"in_flight_max": @(self.maxInFlightCount),
        @"latency_avg": @(avgLatency),
        @"latency_min": @(minLatency),
        @"latency_max": @(self.responseLatencyMax),
    };
}
@end
#endif

@implementation TotalIdentificationController

- (id)initWithSample:(LazySample*)sample
{
    self = [super init];
    if (self) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            NSDictionary<NSString*, id>* defaults = @{
                @"UseStreamingMatch": @YES,
                @"UseSignatureTimes": @YES,
                @"SignatureWindowSeconds": @8.0,
                @"SignatureWindowMaxSeconds": @8.0,
                @"HopSizeFrames": @1048576,
                @"DownmixToMono": @YES,
                @"ExcludeUnknownInputs": @YES,
            };
            [[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
        });

        _sample = sample;
        // Live-simulation hop size (~4096 frames), with optional override via defaults.
        AVAudioFrameCount hopSize = (AVAudioFrameCount)4096;
        double hopOverride = [[NSUserDefaults standardUserDefaults] doubleForKey:@"HopSizeFrames"];
        if (hopOverride > 0.0) {
            hopSize = (AVAudioFrameCount)hopOverride;
        }
        AVAudioFrameCount maxHopFrames = (AVAudioFrameCount)(12.0 * sample.sampleFormat.rate);
        if (maxHopFrames > 0 && hopSize > maxHopFrames) {
            hopSize = maxHopFrames;
            if (_debugScoring) {
                NSLog(@"[Detect] hopSizeFrames clamped to %u (12s max signature window)", (unsigned int)hopSize);
            }
        }
        _hopSize = hopSize;
        _identifieds = [NSMutableArray array];
        _identifyQueue = dispatch_queue_create("com.playem.identification.queue", DISPATCH_QUEUE_SERIAL);

        NSMutableArray* buffers = [NSMutableArray array];
        for (int channel = 0; channel < sample.sampleFormat.channels; channel++) {
            NSMutableData* buffer = [NSMutableData dataWithCapacity:_hopSize * _sample.frameSize];
            [buffers addObject:buffer];
        }
        _sampleBuffers = buffers;
        _pendingMatchOffsets = [NSMutableArray array];
        _lastMatchFrameByID = [NSMutableDictionary dictionary];
        _requestStartTimeByOffset = [NSMutableDictionary dictionary];
        _requestSliceHashByOffset = [NSMutableDictionary dictionary];
        _shazamRunID = [[NSUUID UUID] UUIDString];
        _firstMatchFrame = ULLONG_MAX;
        _matchFrames = [NSMutableArray array];
        _lastProgressLogged = -1.0;
        _maxInFlightRequests = 1;
        _matchInFlightSemaphore = dispatch_semaphore_create((long)_maxInFlightRequests);
        _inFlightCount = 0;
        _maxInFlightCount = 0;
        _responseLatencySum = 0.0;
        _responseLatencyMin = DBL_MAX;
        _responseLatencyMax = 0.0;
        _idealTrackMinSeconds = 3.0 * 60.0;
        _idealTrackMaxSeconds = 10.0 * 60.0;
        _minScoreThreshold = 0.2;
        _duplicateMergeWindowSeconds = 60.0;
        _debugScoring = YES;
        _referenceArtist = nil;
    }
    return self;
}

@end

NS_ASSUME_NONNULL_END
