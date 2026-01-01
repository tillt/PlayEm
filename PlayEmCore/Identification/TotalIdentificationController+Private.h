//
//  TotalIdentificationController+Private.h
//  PlayEm
//
//  Created by Till Toenshoff on 12/26/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import "TotalIdentificationController.h"
#import <AVFoundation/AVFoundation.h>

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
    BOOL _finishedFeeding;
    BOOL _completionSent;
    void (^_completionHandler)(BOOL, NSError* _Nullable, NSArray<TimedMediaMetaData*>* _Nullable);
    NSMutableArray<NSNumber*>* _pendingMatchOffsets;
    unsigned long long _totalFrameCursor;
    dispatch_queue_t _feedQueue;
    NSMutableDictionary<NSString*, NSNumber*>* _lastMatchFrameByID;
    unsigned long long _minMatchSpacingFrames;
    double _idealTrackMinSeconds;
    double _idealTrackMaxSeconds;
    double _minScoreThreshold;
    double _duplicateMergeWindowSeconds;
    dispatch_block_t _queueOperation;
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
@property (assign, nonatomic) BOOL finishedFeeding;
@property (assign, nonatomic) BOOL completionSent;
@property (copy, nonatomic) void (^completionHandler)(BOOL, NSError* _Nullable, NSArray<TimedMediaMetaData*>* _Nullable);
@property (strong, nonatomic) NSMutableArray<NSNumber*>* pendingMatchOffsets;
@property (assign, nonatomic) unsigned long long totalFrameCursor;
@property (strong, nonatomic) dispatch_queue_t feedQueue;
@property (strong, nonatomic) NSMutableDictionary<NSString*, NSNumber*>* lastMatchFrameByID;
@property (assign, nonatomic) unsigned long long minMatchSpacingFrames;
@property (assign, nonatomic) double idealTrackMinSeconds;
@property (assign, nonatomic) double idealTrackMaxSeconds;
@property (assign, nonatomic) double minScoreThreshold;
@property (assign, nonatomic) double duplicateMergeWindowSeconds;
@property (strong, nonatomic) dispatch_block_t queueOperation;
@property (strong, nonatomic) ActivityToken* token;

@end

NS_ASSUME_NONNULL_END
