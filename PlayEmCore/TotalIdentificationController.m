//
//  TotalIdentificationController.m
//  PlayEm
//
//  Created by Till Toenshoff on 12/26/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import "TotalIdentificationController.h"
#import <ShazamKit/ShazamKit.h>

#import "Sample/LazySample.h"
#import "Metadata/TimedMediaMetaData.h"
#import "ImageController.h"
#import "ActivityManager.h"

NS_ASSUME_NONNULL_BEGIN

static BOOL IsUnknownTrack(TimedMediaMetaData* _Nullable t)
{
    if (t == nil) { return NO; }
    NSString* title = [[t.meta.title ?: @"" precomposedStringWithCanonicalMapping] lowercaseString];
    NSString* artist = [[t.meta.artist ?: @"" precomposedStringWithCanonicalMapping] lowercaseString];
    BOOL titleUnknown = (title.length == 0 || [title isEqualToString:@"unknown"]);
    BOOL artistUnknown = (artist.length == 0 || [artist isEqualToString:@"unknown"]);
    return titleUnknown && artistUnknown;
}

@interface TotalIdentificationController()
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
@property (assign, nonatomic) NSTimeInterval completionGraceSeconds;
@property (copy, nonatomic) void (^completionHandler)(BOOL, NSError* _Nullable, NSArray<TimedMediaMetaData*>* _Nullable);
@property (strong, nonatomic) dispatch_block_t completionDeadlineBlock;
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


// Test-only setter to inject raw hits for refinement without exposing the property publicly.
#ifdef DEBUG
@interface TotalIdentificationController (TestingAccess)
- (void)testing_setIdentifieds:(NSArray<TimedMediaMetaData *> *)hits;
@end

@implementation TotalIdentificationController (TestingAccess)
- (void)testing_setIdentifieds:(NSArray<TimedMediaMetaData *> *)hits
{
    self.identifieds = [hits mutableCopy];
}
@end
#endif

@implementation TotalIdentificationController

- (id)initWithSample:(LazySample*)sample
{
    self = [super init];
    if (self) {
        _sample = sample;
        // Use a larger hop size for offline detection to reduce Shazam request count (~2s chunks).
        _hopSize = (AVAudioFrameCount)4096 * 256;
        _identifieds = [NSMutableArray array];
        _completionGraceSeconds = 0.1; // give Shazam callbacks room after feeding
        _identifyQueue = dispatch_queue_create("com.playem.identification.queue", DISPATCH_QUEUE_SERIAL);
        _feedQueue = dispatch_queue_create("com.playem.identification.feed", DISPATCH_QUEUE_SERIAL);

        NSMutableArray* buffers = [NSMutableArray array];
        for (int channel = 0; channel < sample.sampleFormat.channels; channel++) {
            NSMutableData* buffer = [NSMutableData dataWithCapacity:_hopSize * _sample.frameSize];
            [buffers addObject:buffer];
        }
        _sampleBuffers = buffers;
        _pendingMatchOffsets = [NSMutableArray array];
        _lastMatchFrameByID = [NSMutableDictionary dictionary];
        _idealTrackMinSeconds = 4.0 * 60.0;
        _idealTrackMaxSeconds = 12.0 * 60.0;
        _minScoreThreshold = 0.2;
        _duplicateMergeWindowSeconds = 90.0;
        _debugScoring = YES;
        _referenceArtist = nil;
    }
    return self;
}

- (BOOL)detectTracklist
{
    NSLog(@"detectTracklist");
    self->_session = [[SHSession alloc] init];
    self->_session.delegate = self;

    SampleFormat sampleFormat = self->_sample.sampleFormat;

    AVAudioFrameCount matchWindowFrameCount = self->_hopSize;
    AVAudioChannelLayout* layout = [[AVAudioChannelLayout alloc] initWithLayoutTag:kAudioChannelLayoutTag_Mono];
    AVAudioFormat* format = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                                             sampleRate:sampleFormat.rate
                                                            interleaved:NO
                                                          channelLayout:layout];
    
    AVAudioPCMBuffer* stream = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:matchWindowFrameCount];
    
    float* data[self->_sample.sampleFormat.channels];
    const int channels = self->_sample.sampleFormat.channels;
    for (int channel = 0; channel < channels; channel++) {
        data[channel] = (float*)((NSMutableData*)self->_sampleBuffers[channel]).bytes;
    }

#ifdef DEBUG_TAPPING
    FILE* fp = fopen("/tmp/debug_tap.out", "wb");
#endif
    // Pace offline feeding to roughly match live playback signature cadence x32. Anything
    // faster appears to trash the recognition - it feels like buffers get overwritten but
    // that is not clear, so far. Needs more investigation. Also the fact that we need to
    // rely on sleeps is very hacky - we need proper events - maybe KVO?
    useconds_t throttleUsec = (useconds_t)(((double)_hopSize / sampleFormat.rate / 32.0) * 1000000.0);
    if (throttleUsec < 1) {
        throttleUsec = 1;
    }

    // Here we go, all the way through our entire sample.
    while (self->_totalFrameCursor < self->_sample.frames) {
        if (dispatch_block_testcancel(self.queueOperation) != 0) {
            NSLog(@"aborted track detection");
            return NO;
        }
        double progress = (double)self->_totalFrameCursor / self->_sample.frames;
        [[ActivityManager shared] updateActivity:self->_token progress:progress];
        
        unsigned long long sourceWindowFrameCount = MIN(matchWindowFrameCount,
                                                        self->_sample.frames - self->_totalFrameCursor);
        // This may block for a loooooong time!
        unsigned long long received = [self->_sample rawSampleFromFrameOffset:self->_totalFrameCursor
                                                                       frames:sourceWindowFrameCount
                                                                      outputs:data];
        
        unsigned long int sourceFrameIndex = 0;
        while(sourceFrameIndex < received) {
            if (dispatch_block_testcancel(self.queueOperation) != 0) {
                NSLog(@"aborted track detection");
                return NO;
            }
            
            const unsigned long int inputWindowFrameCount = MIN(matchWindowFrameCount, self->_sample.frames - (self->_totalFrameCursor + sourceFrameIndex));
            
            [stream setFrameLength:(unsigned int)inputWindowFrameCount];
            // TODO: Yikes, this is a total nono -- we are writing to a read-only pointer!
            float* outputBuffer = stream.floatChannelData[0];
            
            unsigned long long chunkStartFrame = self->_totalFrameCursor + sourceFrameIndex;
            for (unsigned long int outputFrameIndex = 0; outputFrameIndex < inputWindowFrameCount; outputFrameIndex++) {
                double s = 0.0;
                for (int channel = 0; channel < sampleFormat.channels; channel++) {
                    s += data[channel][sourceFrameIndex];
                }
                s /= (float)sampleFormat.channels;
                
                outputBuffer[outputFrameIndex] = s;
                sourceFrameIndex++;
            }
            self->_sessionFrameOffset = chunkStartFrame;
            NSNumber* offset = [NSNumber numberWithUnsignedLongLong:chunkStartFrame];
            @synchronized (self) {
                [self->_pendingMatchOffsets addObject:offset];
            }

            AVAudioTime* time = [AVAudioTime timeWithSampleTime:chunkStartFrame atRate:sampleFormat.rate];
            self->_matchRequestCount += 1;

            [self->_session matchStreamingBuffer:stream atTime:time];

            // Light pacing so callbacks have a chance to arrive; ~16x realtime.
            usleep(throttleUsec);
        };
        self->_totalFrameCursor += received;
    };
    self->_finishedFeeding = YES;
    return YES;
}

- (ActivityToken*)detectTracklistWithCallback:(nonnull void (^)(BOOL, NSError*, NSArray<TimedMediaMetaData*>*))callback
{
    __block BOOL done = NO;
    __weak typeof(self) weakSelf = self;
    
    self->_completionHandler = [callback copy];
    [self->_identifieds removeAllObjects];
    self->_matchRequestCount = 0;
    self->_matchResponseCount = 0;
    self->_finishedFeeding = NO;
    self->_completionSent = NO;
    self->_totalFrameCursor = 0;
    [self->_pendingMatchOffsets removeAllObjects];

    if (self->_completionDeadlineBlock) {
        dispatch_block_cancel(self->_completionDeadlineBlock);
        self->_completionDeadlineBlock = nil;
    }

    _token = [[ActivityManager shared] beginActivityWithTitle:@"Tracklist Detection" detail:nil cancellable:YES cancelHandler:^{
        [weakSelf abortWithCallback:^{
            [[ActivityManager shared] updateActivity:self->_token detail:@"aborted"];
            [[ActivityManager shared] completeActivity:self->_token];
            self->_completionHandler(NO, nil, nil);
        }];
    }];

    _queueOperation = dispatch_block_create(DISPATCH_BLOCK_NO_QOS_CLASS, ^{
        done = [weakSelf detectTracklist];
        [weakSelf scheduleCompletionCheckIsTimeout:NO];
    });
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), _queueOperation);

    NSLog(@"starting track list detection");
    return _token;
}

- (void)abortWithCallback:(void (^)(void))callback
{
    NSLog(@"abort of track detection ongoing..");
    if (_queueOperation != NULL) {
        dispatch_block_cancel(_queueOperation);
        dispatch_block_notify(_queueOperation, dispatch_get_main_queue(), ^{
            callback();
        });
    } else {
        callback();
    }
}

- (double)estimatedDurationForTrack:(TimedMediaMetaData*)track nextTrack:(TimedMediaMetaData* _Nullable)next
{
    double durationSeconds = 0.0;
    double sampleRate = (double)self->_sample.sampleFormat.rate;
    if (track.meta.duration != nil) {
        durationSeconds = track.meta.duration.doubleValue;
    } else if (track.endFrame != nil && track.frame != nil && track.endFrame.unsignedLongLongValue > track.frame.unsignedLongLongValue && sampleRate > 0.0) {
        // Use span between first and last detection of the same key.
        double frameSpan = (double)(track.endFrame.unsignedLongLongValue - track.frame.unsignedLongLongValue);
        durationSeconds = frameSpan / sampleRate;
    } else if (next != nil && track.frame != nil && next.frame != nil && sampleRate > 0.0) {
        // Estimate duration from frame gap.
        double frameGap = (double)(next.frame.unsignedLongLongValue - track.frame.unsignedLongLongValue);
        durationSeconds = frameGap / sampleRate;
    } else if (track.frame != nil && sampleRate > 0.0) {
        // Fallback: time from this frame to the end of the sample.
        double frameGap = (double)(self->_sample.frames - track.frame.unsignedLongLongValue);
        durationSeconds = frameGap / sampleRate;
    }
    return durationSeconds;
}

- (unsigned long long)estimatedEndFrameForTrack:(TimedMediaMetaData*)track nextTrack:(TimedMediaMetaData* _Nullable)next
{
    double start = track.frame != nil ? track.frame.doubleValue : 0.0;
    double sampleRate = (double)self->_sample.sampleFormat.rate;
    double durationSeconds = [self estimatedDurationForTrack:track nextTrack:next];

    // If we already have a last detection frame, prefer that over derived duration.
    if (track.endFrame != nil && track.endFrame.unsignedLongLongValue > (track.frame != nil ? track.frame.unsignedLongLongValue : 0)) {
        return track.endFrame.unsignedLongLongValue;
    }
    if (durationSeconds <= 0.0 || sampleRate <= 0.0) {
        return (unsigned long long)start;
    }
    double frames = durationSeconds * sampleRate;
    return (unsigned long long)(start + frames);
}

//
// Adaptive Confidence Blending
//
//    Collect hits: Accumulate Shazam matches into TimedMediaMetaData items (frame, meta, optional endFrame). Require support ≥ 2
//    per normalized key (artist — title) before keeping a candidate; otherwise drop.
//
//    Aggregate & build tracks: For each key, track earliest frame, latest frame, support count, and representative metadata. Create
//    track objects with frame, endFrame, support/confidence.
//
//    Sort by start frame.
//
//    Score each track:
//      Base = support count (no cap).
//      Duration estimate: metadata duration if present; else span frame→endFrame; else gap to next track; else to sample end. If
//                         support≥2 and duration < ideal min, clamp up to the ideal min.
//      Duration weight:   ideal window 4–12 min → 1.6× boost; <3 min heavy penalty; short (<4 min) quadratic falloff; long penalty with 0.15 floor.
//      Producer bonus:    if referenceArtist appears in artist/title, ×3.
//
//    Set score and confidence to the final value.
//
//    Merge near-duplicates: Within 90 s, if titles/artists match/overlap, keep the higher score.
//
//    Overlap resolution: Walk in time order; if spans overlap, keep higher score. Real tracks always beat “unknown” placeholders.
//
//    Gap fill (unknowns): For gaps between kept tracks, if there are ≥3 unknown hits spanning ≥60 s (and under the ideal max), synthesize an
//                         “Unknown” track covering that span, score it via the same duration heuristic, and reinsert.
//
//    Short/low drop (late): After all above, drop items with score ≤ 5 and duration < 90 s.
//
- (NSArray<TimedMediaMetaData*>*)refineTracklist
{
    NSArray<TimedMediaMetaData*>* input = nil;
    @synchronized (self) {
        input = [_identifieds copy];
    }

    if (input.count == 0) {
        return @[];
    }
    
    // Emit final kept list when debugging so we can see what survived all passes.
    if (_debugScoring) {
        for (TimedMediaMetaData* t in input) {
            NSLog(@"[Input] frame:%@ artist:%@ title:%@ score:%.3f confidence:%@",
                  t.frame,
                  t.meta.artist ?: @"",
                  t.meta.title ?: @"",
                  t.score.doubleValue,
                  t.confidence);
        }
    }

    NSString* (^normKey)(TimedMediaMetaData*) = ^NSString* (TimedMediaMetaData* t) {
        NSString* artist = t.meta.artist ?: @"";
        NSString* title = t.meta.title ?: @"";
        NSString* key = [NSString stringWithFormat:@"%@ — %@", artist, title];
        key = [[key precomposedStringWithCanonicalMapping] lowercaseString];
        key = [key stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return key;
    };

    // Aggregate earliest frame and highest-confidence representative per normalized key.
    NSMutableDictionary<NSString*, NSMutableDictionary*>* agg = [NSMutableDictionary dictionary];
    NSInteger maxSupportObserved = 0;
    for (TimedMediaMetaData* t in input) {
        if (t.meta.title.length == 0 || t.frame == nil) {
            continue;
        }
        NSString* k = normKey(t);
        if (k.length == 0) {
            continue;
        }

        NSMutableDictionary* entry = agg[k];
        if (entry == nil) {
            entry = [@{@"frame": t.frame,
                       @"lastFrame": t.frame,
                       @"count": @(1),
                       @"meta": t.meta ?: [NSNull null],
                       @"confidence": t.confidence ?: [NSNull null]} mutableCopy];
            agg[k] = entry;
        } else {
            entry[@"count"] = @([entry[@"count"] integerValue] + 1);

            NSNumber* existingFrame = entry[@"frame"];
            if (t.frame.unsignedLongLongValue < existingFrame.unsignedLongLongValue) {
                entry[@"frame"] = t.frame;
                // Prefer earliest occurrence as the representative payload.
                entry[@"meta"] = t.meta ?: [NSNull null];
                entry[@"confidence"] = t.confidence ?: [NSNull null];
            } else if (entry[@"meta"] == [NSNull null] && t.meta != nil) {
                entry[@"meta"] = t.meta;
                entry[@"confidence"] = t.confidence ?: [NSNull null];
            }
            // Track the latest frame seen for this key.
            NSNumber* last = entry[@"lastFrame"];
            if (last == nil || t.frame.unsignedLongLongValue > last.unsignedLongLongValue) {
                entry[@"lastFrame"] = t.frame;
            }
        }

        if ([entry[@"count"] integerValue] > maxSupportObserved) {
            maxSupportObserved = [entry[@"count"] integerValue];
        }
    }

    if (agg.count == 0) {
        return @[];
    }

    // Static support threshold to keep logic simple. Allow single hits to be considered so
    // refinement can lean on duration/producer heuristics instead of discarding them early.
    NSInteger dynamicMinSupport = 1;

    NSMutableArray<TimedMediaMetaData*>* result = [NSMutableArray array];
    for (NSString* key in agg) {
        NSDictionary* entry = agg[key];
        NSInteger count = [entry[@"count"] integerValue];
        if (count < dynamicMinSupport) {
            continue;
        }
        TimedMediaMetaData* t = [TimedMediaMetaData new];
        if (entry[@"meta"] != [NSNull null]) {
            t.meta = entry[@"meta"];
        }
        t.frame = entry[@"frame"];
        t.endFrame = entry[@"lastFrame"];
        t.supportCount = @(count);
        t.confidence = @(count);
        [result addObject:t];
    }

    // If nothing met the threshold, keep the single strongest key as a fallback.
    if (result.count == 0 && agg.count > 0) {
        __block NSString* bestKey = nil;
        __block NSInteger bestCount = 0;
        __block NSNumber* bestFrame = nil;
        [agg enumerateKeysAndObjectsUsingBlock:^(NSString* key, NSDictionary* entry, BOOL* stop) {
            NSInteger c = [entry[@"count"] integerValue];
            if (c > bestCount) {
                bestCount = c;
                bestKey = key;
                bestFrame = entry[@"frame"];
            } else if (c == bestCount && bestFrame != nil) {
                NSNumber* frame = entry[@"frame"];
                if (frame.unsignedLongLongValue < bestFrame.unsignedLongLongValue) {
                    bestKey = key;
                    bestFrame = frame;
                }
            }
        }];
        if (bestKey) {
            NSDictionary* entry = agg[bestKey];
            TimedMediaMetaData* t = [TimedMediaMetaData new];
            id meta = entry[@"meta"];
            if (meta != [NSNull null]) {
                t.meta = meta;
            }
            t.frame = entry[@"frame"];
            t.endFrame = entry[@"lastFrame"];
            t.supportCount = entry[@"count"];
            t.confidence = entry[@"count"];
            [result addObject:t];
        }
    }

    [result sortUsingComparator:^NSComparisonResult(TimedMediaMetaData* a, TimedMediaMetaData* b) {
        return [a.frame compare:b.frame];
    }];

    // After sorting, recompute duration/producer-based scores using neighbors and reflect into confidence.
    for (NSUInteger i = 0; i < result.count; i++) {
        TimedMediaMetaData* current = result[i];
        // Find the next track with a strictly greater frame to estimate duration.
        TimedMediaMetaData* next = nil;
        for (NSUInteger j = i + 1; j < result.count; j++) {
            if (result[j].frame.unsignedLongLongValue > current.frame.unsignedLongLongValue) {
                next = result[j];
                break;
            }
        }
        double s = [self scoreForTrack:current nextTrack:next];
        current.score = @(s);
        current.confidence = @(s);
        if (_debugScoring) {
            NSString* title = current.meta.title ?: @"";
            NSString* artist = current.meta.artist ?: @"";
            double durationSeconds = [self estimatedDurationForTrack:current nextTrack:next];
            NSLog(@"[Score] frame:%@ artist:%@ title:%@ duration:%.2fs score:%.3f confidence:%@", current.frame, artist, title, durationSeconds, s, current.confidence);
        }
    }

    // Merge near-duplicates (same/related track within a small time window), keeping the higher-scoring one.
    double windowFrames = _duplicateMergeWindowSeconds * (double)self->_sample.sampleFormat.rate;
    NSMutableArray<TimedMediaMetaData*>* pruned = [NSMutableArray array];
    for (NSUInteger i = 0; i < result.count; i++) {
        TimedMediaMetaData* current = result[i];
        BOOL merged = NO;
        for (NSUInteger j = i + 1; j < result.count; j++) {
            TimedMediaMetaData* other = result[j];
            if (other.frame.unsignedLongLongValue - current.frame.unsignedLongLongValue > windowFrames) {
                break;
            }
            if ([self isSimilarTrack:current other:other]) {
                TimedMediaMetaData* winner = current.score.doubleValue >= other.score.doubleValue ? current : other;
                TimedMediaMetaData* loser = (winner == current) ? other : current;
                if (winner == other) {
                    merged = YES;
                }
                if (_debugScoring) {
                    NSLog(@"[Score] merging similar tracks at frames %@/%@ -> keeping %@ %@ (score %.3f) dropping %@ %@ (score %.3f)",
                          current.frame, other.frame,
                          winner.meta.artist ?: @"", winner.meta.title ?: @"", winner.score.doubleValue,
                          loser.meta.artist ?: @"", loser.meta.title ?: @"", loser.score.doubleValue);
                }
                // Skip adding loser; advance i to winner position.
                current = winner;
            }
        }
        [pruned addObject:current];
    }

    result = pruned;

    // Enforce a simple non-overlap rule: walk in frame order and keep the higher-scoring
    // track when two spans would overlap. We always favor the higher score, regardless
    // of order, so strong tracks push out weaker overlapping candidates. Duration is
    // estimated from either metadata, the span of repeated detections, or gap to the next track.
    NSMutableArray<TimedMediaMetaData*>* nonOverlapping = [NSMutableArray array];
    TimedMediaMetaData* lastKept = nil;
    unsigned long long lastEnd = 0;
    double lastScore = 0.0;
    for (NSUInteger i = 0; i < result.count; i++) {
        TimedMediaMetaData* current = result[i];
        TimedMediaMetaData* lookahead = (i + 1 < result.count) ? result[i + 1] : nil;
        unsigned long long start = current.frame != nil ? current.frame.unsignedLongLongValue : 0;
        unsigned long long end = [self estimatedEndFrameForTrack:current nextTrack:lookahead];
        double score = current.score != nil ? current.score.doubleValue : 0.0;

        if (nonOverlapping.count == 0) {
            [nonOverlapping addObject:current];
            lastKept = current;
            lastEnd = end;
            lastScore = score;
            continue;
        }

        if (start < lastEnd) {
            // Overlap: keep the higher-scoring of the two regardless of order.
            BOOL lastIsUnknown = IsUnknownTrack(lastKept);
            BOOL currentIsUnknown = IsUnknownTrack(current);

            // Prefer real tracks over "unknown" filler regardless of score.
            if (lastIsUnknown && !currentIsUnknown) {
                [nonOverlapping removeLastObject];
                [nonOverlapping addObject:current];
                lastKept = current;
                lastEnd = end;
                lastScore = score;
            } else if (!lastIsUnknown && currentIsUnknown) {
                // Drop the unknown overlap; keep the real track already kept.
                continue;
            } else if (score > lastScore) {
                [nonOverlapping removeLastObject];
                [nonOverlapping addObject:current];
                lastKept = current;
                lastEnd = end;
                lastScore = score;
            } else {
                // Keep previous; drop current.
            }
        } else {
            [nonOverlapping addObject:current];
            lastKept = current;
            lastEnd = end;
            lastScore = score;
        }
    }

    result = nonOverlapping;

    // Fill gaps with sustained "unknown" detections (high repetition) without letting them displace real tracks.
    result = [self fillGapsWithUnknownsIn:result rawInput:input];

    // Apply the short/low filter late, after overlaps and gap fill.
    NSMutableArray<TimedMediaMetaData*>* filtered = [NSMutableArray array];
    for (NSUInteger i = 0; i < result.count; i++) {
        TimedMediaMetaData* current = result[i];
        TimedMediaMetaData* next = (i + 1 < result.count) ? result[i + 1] : nil;
        double durationSeconds = [self estimatedDurationForTrack:current nextTrack:next];
        double s = current.score != nil ? current.score.doubleValue : 0.0;
        const double shortCutoffSeconds = 90.0; // ~1.5 minutes
        if (s <= 5.0 && durationSeconds > 0.0 && durationSeconds < shortCutoffSeconds) {
            if (_debugScoring) {
                NSLog(@"[Score] dropping low-score short candidate at frame %@ (duration %.2fs score %.3f)", current.frame, durationSeconds, s);
            }
            continue;
        }
        [filtered addObject:current];
    }

    result = filtered;

    // Emit final kept list when debugging so we can see what survived all passes.
    if (_debugScoring) {
        for (TimedMediaMetaData* t in result) {
            double durationSeconds = [self estimatedDurationForTrack:t nextTrack:nil];
            NSLog(@"[Final] frame:%@ artist:%@ title:%@ duration:%.2fs score:%.3f confidence:%@",
                  t.frame,
                  t.meta.artist ?: @"",
                  t.meta.title ?: @"",
                  durationSeconds,
                  t.score.doubleValue,
                  t.confidence);
        }
    }

    return result;
}

- (double)scoreForTrack:(TimedMediaMetaData*)track nextTrack:(TimedMediaMetaData* _Nullable)next
{
    // Base score starts from support or the prior confidence.
    // We intentionally let support scale freely (no cap) so a strongly repeated hit
    // can dominate and push out unlikely, short-lived candidates.
    double base = 1.0;
    if (track.supportCount != nil) {
        base = track.supportCount.doubleValue;
    } else if (track.confidence != nil) {
        base = track.confidence.doubleValue;
    }

    // Duration heuristic: prefer 4–8 minutes. Estimate duration from metadata if present, otherwise from spacing to next track.
    double durationSeconds = [self estimatedDurationForTrack:track nextTrack:next];

    double durationScore = 1.0;
    if (durationSeconds <= 0.0) {
        // Unknown duration: penalize.
        durationScore = 0.05;
    } else if (durationSeconds < 90.0) {
        // Very short (<1.5min): heavily penalize regardless of support.
        durationScore = 0.01;
    } else if (durationSeconds >= _idealTrackMinSeconds && durationSeconds <= _idealTrackMaxSeconds) {
        // Ideal window: strongly reward a solid, full-length track.
        durationScore = 1.60;
    } else if (durationSeconds < _idealTrackMinSeconds) {
        // Short: steeper quadratic falloff; floor at 0.05.
        double ratio = durationSeconds / _idealTrackMinSeconds; // 0..1
        durationScore = MAX(0.05, 0.8 * ratio * ratio);
    } else {
        // Penalize long tracks; make the penalty a bit stronger, floor at 0.15.
        double ratio = _idealTrackMaxSeconds / durationSeconds;
        durationScore = MAX(0.15, 0.8 * ratio);
    }

    double score = base * durationScore;

    // Producer/artist bonus: if the reference artist appears in the detected artist or title, boost strongly.
    NSString* refArtist = self.referenceArtist;
    if (refArtist.length > 0) {
        NSString* (^norm)(NSString*) = ^NSString* (NSString* s) {
            if (s == nil) {
                return @"";
            }
            return [[s precomposedStringWithCanonicalMapping] lowercaseString];
        };
        NSString* normalizedRef = norm(refArtist);
        NSString* normalizedArtist = norm(track.meta.artist);
        NSString* normalizedTitle = norm(track.meta.title);

        if ([normalizedArtist containsString:normalizedRef] || [normalizedTitle containsString:normalizedRef]) {
            // strong boost when the producer/artist name is present
            score *= 3.0;
        }
    }

    if (_debugScoring) {
        NSInteger support = track.supportCount != nil ? track.supportCount.integerValue : 0;
        NSString* artist = track.meta.artist ?: @"";
        NSString* title = track.meta.title ?: @"";
        NSLog(@"[ScoreDetail] frame:%@ support:%ld base:%.3f duration:%.2fs durationScore:%.3f ref:%@ final:%.3f",
              track.frame,
              (long)support,
              base,
              durationSeconds,
              durationScore,
              (refArtist.length > 0 ? @"yes" : @"no"),
              score);
    }

    return score;
}

- (NSArray<TimedMediaMetaData*>*)fillGapsWithUnknownsIn:(NSArray<TimedMediaMetaData*>*)tracks rawInput:(NSArray<TimedMediaMetaData*>*)input
{
    if (tracks.count == 0 || input.count == 0) {
        return tracks;
    }
    // Collect unknown hits from raw input.
    NSMutableArray<TimedMediaMetaData*>* unknownHits = [NSMutableArray array];
    for (TimedMediaMetaData* t in input) {
        if (IsUnknownTrack(t) && t.frame != nil) {
            [unknownHits addObject:t];
        }
    }
    if (unknownHits.count == 0) {
        return tracks;
    }
    // Sort hits by frame.
    [unknownHits sortUsingComparator:^NSComparisonResult(TimedMediaMetaData* a, TimedMediaMetaData* b) {
        return [a.frame compare:b.frame];
    }];

    NSMutableArray<TimedMediaMetaData*>* augmented = [tracks mutableCopy];
    double sampleRate = (double)self->_sample.sampleFormat.rate;

    unsigned long long lastEnd = 0;
    for (NSUInteger i = 0; i <= tracks.count; i++) {
        unsigned long long gapStart = lastEnd;
        unsigned long long gapEnd = (i < tracks.count) ? tracks[i].frame.unsignedLongLongValue : self->_sample.frames;
        if (gapEnd <= gapStart || gapEnd == 0) {
            if (i < tracks.count) {
                lastEnd = [self estimatedEndFrameForTrack:tracks[i] nextTrack:(i + 1 < tracks.count ? tracks[i + 1] : nil)];
            }
            continue;
        }
        // Gather unknown hits within this gap.
        NSMutableArray<TimedMediaMetaData*>* hitsInGap = [NSMutableArray array];
        for (TimedMediaMetaData* hit in unknownHits) {
            unsigned long long f = hit.frame.unsignedLongLongValue;
            if (f >= gapStart && f < gapEnd) {
                [hitsInGap addObject:hit];
            }
        }
        if (hitsInGap.count == 0) {
            if (i < tracks.count) {
                lastEnd = [self estimatedEndFrameForTrack:tracks[i] nextTrack:(i + 1 < tracks.count ? tracks[i + 1] : nil)];
            }
            continue;
        }
        unsigned long long first = hitsInGap.firstObject.frame.unsignedLongLongValue;
        unsigned long long last = hitsInGap.lastObject.frame.unsignedLongLongValue;
        unsigned long long spanFrames = (last > first) ? (last - first) : 0;
        double spanSeconds = sampleRate > 0.0 ? ((double)spanFrames / sampleRate) : 0.0;
        NSInteger support = hitsInGap.count;

        // Require decent repetition and a sensible span.
        if (support < 3) {
            if (i < tracks.count) {
                lastEnd = [self estimatedEndFrameForTrack:tracks[i] nextTrack:(i + 1 < tracks.count ? tracks[i + 1] : nil)];
            }
            continue;
        }
        if (spanSeconds < 60.0 || spanSeconds > _idealTrackMaxSeconds) {
            if (i < tracks.count) {
                lastEnd = [self estimatedEndFrameForTrack:tracks[i] nextTrack:(i + 1 < tracks.count ? tracks[i + 1] : nil)];
            }
            continue;
        }

        TimedMediaMetaData* unknown = [TimedMediaMetaData unknownTrackAtFrame:@(first)];
        unknown.endFrame = @(last);
        unknown.supportCount = @(support);
        // Score using duration heuristic.
        double s = [self scoreForTrack:unknown nextTrack:nil];
        unknown.score = @(s);
        unknown.confidence = @(s);
        [augmented addObject:unknown];

        if (i < tracks.count) {
            lastEnd = [self estimatedEndFrameForTrack:tracks[i] nextTrack:(i + 1 < tracks.count ? tracks[i + 1] : nil)];
        }
    }

    // Re-sort and run overlap once more to let real tracks win.
    [augmented sortUsingComparator:^NSComparisonResult(TimedMediaMetaData* a, TimedMediaMetaData* b) {
        return [a.frame compare:b.frame];
    }];
    return augmented;
}

- (BOOL)isSimilarTrack:(TimedMediaMetaData*)a other:(TimedMediaMetaData*)b
{
    NSString* (^norm)(NSString*) = ^NSString* (NSString* s) {
        if (s == nil) { return @""; }
        NSString* n = [[s precomposedStringWithCanonicalMapping] lowercaseString];
        return [n stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    };

    NSString* artistA = norm(a.meta.artist);
    NSString* artistB = norm(b.meta.artist);
    NSString* titleA = norm(a.meta.title);
    NSString* titleB = norm(b.meta.title);

    BOOL artistMatch = artistA.length > 0 && [artistA isEqualToString:artistB];
    BOOL titleOverlap = (titleA.length > 0 && titleB.length > 0 &&
                         ([titleA containsString:titleB] || [titleB containsString:titleA]));

    return artistMatch || titleOverlap;
}

- (void)fireCompletion
{
    if (_completionSent) {
        return;
    }
    _completionSent = YES;
    if (_completionDeadlineBlock) {
        dispatch_block_cancel(_completionDeadlineBlock);
        _completionDeadlineBlock = nil;
    }
    
    NSLog(@"firing completion after %lu requests / %lu responses (finishedFeeding=%d)",
          (unsigned long)_matchRequestCount,
          (unsigned long)_matchResponseCount,
          _finishedFeeding);

    [[ActivityManager shared] updateActivity:_token detail:@"refining tracklist"];
    NSArray<TimedMediaMetaData*>* refined = [self refineTracklist];

    [[ActivityManager shared] updateActivity:_token detail:@"refinement done"];
    [[ActivityManager shared] completeActivity:_token];

    if (_completionHandler) {
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            TotalIdentificationController* strongSelf = weakSelf;
            if (strongSelf == nil) {
                NSLog(@"lost myself");
                return;
            }
            strongSelf->_completionHandler(YES, nil, refined);
        });
    }
}

- (void)resetCompletionDeadline
{
    if (_completionSent || !_finishedFeeding) {
        return;
    }
    if (_completionDeadlineBlock) {
        dispatch_block_cancel(_completionDeadlineBlock);
        _completionDeadlineBlock = nil;
    }
    __weak typeof(self) weakSelf = self;
    dispatch_block_t block = dispatch_block_create(0, ^{
        [weakSelf scheduleCompletionCheckIsTimeout:YES];
    });
    _completionDeadlineBlock = block;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_completionGraceSeconds * NSEC_PER_SEC)),
                   _identifyQueue,
                   block);
}

- (void)scheduleCompletionCheckIsTimeout:(BOOL)isTimeout
{
    if (_completionSent) {
        return;
    }
    BOOL haveAllResponses = _finishedFeeding && (_matchResponseCount >= _matchRequestCount);
    if (haveAllResponses || isTimeout) {
        [self fireCompletion];
        return;
    }
    [self resetCompletionDeadline];
}

#pragma mark - Shazam Delegate

- (void)session:(SHSession*)session didFindMatch:(SHMatch*)match
{
    __weak TotalIdentificationController* weakSelf = self;

    NSLog(@"%s", __PRETTY_FUNCTION__);

    dispatch_async(_identifyQueue, ^{
        TotalIdentificationController* strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        NSNumber* offset = nil;
        @synchronized (strongSelf) {
            if (strongSelf->_pendingMatchOffsets.count > 0) {
                offset = strongSelf->_pendingMatchOffsets.firstObject;
                [strongSelf->_pendingMatchOffsets removeObjectAtIndex:0];
            }
        }
        if (offset == nil) {
            offset = [NSNumber numberWithUnsignedLongLong:strongSelf->_sessionFrameOffset];
        }
        TimedMediaMetaData* track = [[TimedMediaMetaData alloc] initWithMatchedMediaItem:match.mediaItems[0] frame:offset];
        
        NSString* msg = [NSString stringWithFormat:@"%@ - %@", track.meta.artist, track.meta.title];
        [[ActivityManager shared] updateActivity:strongSelf->_token detail:msg];
        
        void (^continuation)(void) = ^(void) {
            TotalIdentificationController* strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            [strongSelf->_identifieds addObject:track];
            unsigned long long next = strongSelf->_matchResponseCount + 1;
            strongSelf->_matchResponseCount = MIN(next, strongSelf->_matchRequestCount);
            [strongSelf scheduleCompletionCheckIsTimeout:NO];
        };

        if (track.meta.artworkLocation != nil) {
            [[ImageController shared] resolveDataForURL:track.meta.artworkLocation callback:^(NSData* data){
                track.meta.artwork = data;
                continuation();
            }];
        } else {
            continuation();
        }
    });
}

- (void)session:(SHSession *)session didNotFindMatchForSignature:(SHSignature *)signature error:(nullable NSError *)error
{
    __weak TotalIdentificationController* weakSelf = self;

    NSLog(@"%s: error: %@", __PRETTY_FUNCTION__, error);
    
    dispatch_async(_identifyQueue, ^{
        TotalIdentificationController* strongSelf = weakSelf;
        if (strongSelf != nil) {
            NSNumber* offset = nil;
            @synchronized (strongSelf) {
                if (strongSelf->_pendingMatchOffsets.count > 0) {
                    offset = strongSelf->_pendingMatchOffsets.firstObject;
                    [strongSelf->_pendingMatchOffsets removeObjectAtIndex:0];
                }
            }
            if (offset == nil) {
                offset = [NSNumber numberWithUnsignedLongLong:strongSelf->_sessionFrameOffset];
            }
            TimedMediaMetaData* track = [TimedMediaMetaData unknownTrackAtFrame:offset];

            [[ActivityManager shared] updateActivity:strongSelf->_token detail:track.meta.title];

            [strongSelf->_identifieds addObject:track];
            unsigned long long next = strongSelf->_matchResponseCount + 1;
            strongSelf->_matchResponseCount = MIN(next, strongSelf->_matchRequestCount);
            [strongSelf scheduleCompletionCheckIsTimeout:NO];
        }
    });
}

@end

NS_ASSUME_NONNULL_END
