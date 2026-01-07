//
//  TotalIdentificationController+Private.h
//  PlayEm
//
//  Created by Till Toenshoff on 12/26/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

#import "TotalIdentificationController.h"

@class LazySample;
@class TimedMediaMetaData;
@class ActivityToken;

NS_ASSUME_NONNULL_BEGIN

@interface TotalIdentificationController () {
    SHSession* _session;
    unsigned long long _sessionFrame;
    dispatch_queue_t _identifyQueue;
    NSMutableArray<TimedMediaMetaData*>* _identifieds;
    LazySample* _sample;
    AVAudioFrameCount _hopSize;
    NSArray<NSData*>* _sampleBuffers;
    unsigned long long _sessionFrameOffset;
    NSUInteger _matchRequestCount;
    NSUInteger _matchResponseCount;
    dispatch_semaphore_t _matchInFlightSemaphore;
    NSUInteger _maxInFlightRequests;
    NSUInteger _inFlightCount;
    NSUInteger _maxInFlightCount;
    double _responseLatencySum;
    double _responseLatencyMin;
    double _responseLatencyMax;
    NSMutableDictionary<NSNumber*, NSNumber*>* _requestStartTimeByOffset;
    NSMutableDictionary<NSNumber*, NSString*>* _requestSliceHashByOffset;
    NSString* _shazamRunID;
    unsigned long long _firstMatchFrame;
    NSMutableArray<NSNumber*>* _matchFrames;
    double _lastProgressLogged;
    BOOL _finishedFeeding;
    BOOL _completionSent;
    BOOL _debugScoring;
    void (^_completionHandler)(BOOL, NSError* _Nullable, NSArray<TimedMediaMetaData*>* _Nullable);
    NSMutableArray<NSNumber*>* _pendingMatchOffsets;
    unsigned long long _totalFrameCursor;
    NSMutableDictionary<NSString*, NSNumber*>* _lastMatchFrameByID;
    unsigned long long _minMatchSpacingFrames;
    double _idealTrackMinSeconds;
    double _idealTrackMaxSeconds;
    double _minScoreThreshold;
    double _duplicateMergeWindowSeconds;
    double _signatureWindowSeconds;
    double _signatureWindowMaxSeconds;
    BOOL _useStreamingMatch;
    BOOL _streamingCompletionScheduled;
    dispatch_block_t _queueOperation;
    NSString* _referenceArtist;
    ActivityToken* _token;
}
@property (strong, nonatomic) SHSession* session;
@property (assign, nonatomic) unsigned long long sessionFrame;
@property (strong, nonatomic) dispatch_queue_t identifyQueue;
@property (strong, nonatomic) NSMutableArray<TimedMediaMetaData*>* identifieds;
@property (strong, nonatomic) LazySample* sample;
@property (assign, nonatomic) AVAudioFrameCount hopSize;
@property (strong, nonatomic) NSArray<NSData*>* sampleBuffers;
@property (assign, nonatomic) unsigned long long sessionFrameOffset;
@property (assign, nonatomic) NSUInteger matchRequestCount;
@property (assign, nonatomic) NSUInteger matchResponseCount;
@property (strong, nonatomic) dispatch_semaphore_t matchInFlightSemaphore;
@property (assign, nonatomic) NSUInteger maxInFlightRequests;
@property (assign, nonatomic) NSUInteger inFlightCount;
@property (assign, nonatomic) NSUInteger maxInFlightCount;
@property (assign, nonatomic) double responseLatencySum;
@property (assign, nonatomic) double responseLatencyMin;
@property (assign, nonatomic) double responseLatencyMax;
@property (strong, nonatomic) NSMutableDictionary<NSNumber*, NSNumber*>* requestStartTimeByOffset;
@property (assign, nonatomic) unsigned long long firstMatchFrame;
@property (strong, nonatomic) NSMutableArray<NSNumber*>* matchFrames;
@property (assign, nonatomic) double lastProgressLogged;
@property (assign, nonatomic) BOOL finishedFeeding;
@property (assign, nonatomic) BOOL completionSent;
@property (copy, nonatomic) void (^completionHandler)(BOOL, NSError* _Nullable, NSArray<TimedMediaMetaData*>* _Nullable);
@property (strong, nonatomic) NSMutableArray<NSNumber*>* pendingMatchOffsets;
@property (assign, nonatomic) unsigned long long totalFrameCursor;
@property (strong, nonatomic) NSMutableDictionary<NSString*, NSNumber*>* lastMatchFrameByID;
@property (assign, nonatomic) unsigned long long minMatchSpacingFrames;
@property (assign, nonatomic) double idealTrackMinSeconds;
@property (assign, nonatomic) double idealTrackMaxSeconds;
@property (assign, nonatomic) double minScoreThreshold;
@property (assign, nonatomic) double duplicateMergeWindowSeconds;
@property (assign, nonatomic) double signatureWindowSeconds;
@property (assign, nonatomic) double signatureWindowMaxSeconds;
@property (assign, nonatomic) BOOL useStreamingMatch;
@property (strong, nonatomic) dispatch_block_t queueOperation;
@property (strong, nonatomic) ActivityToken* token;

@end

NS_ASSUME_NONNULL_END
