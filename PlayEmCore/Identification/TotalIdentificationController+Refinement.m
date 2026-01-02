//
//  TotalIdentificationController+Refinement.m
//  PlayEm
//
//  Created by Till Toenshoff on 12/26/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import <fcntl.h>
#import <unistd.h>

#import "TotalIdentificationController+Private.h"
#import "TotalIdentificationController+Refinement.h"

#import "../Sample/LazySample.h"
#import "../Metadata/TimedMediaMetaData.h"

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

static NSString* NormalizeTrackKeyComponent(NSString* value)
{
    if (value == nil) {
        return @"";
    }
    NSString* lower = [[value precomposedStringWithCanonicalMapping] lowercaseString];
    NSCharacterSet* allowed = [NSCharacterSet alphanumericCharacterSet];
    NSMutableString* cleaned = [NSMutableString stringWithCapacity:lower.length];
    for (NSUInteger i = 0; i < lower.length; i++) {
        unichar ch = [lower characterAtIndex:i];
        if ([allowed characterIsMember:ch]) {
            [cleaned appendFormat:@"%C", ch];
        } else {
            [cleaned appendString:@" "];
        }
    }
    NSArray<NSString*>* parts = [cleaned componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableArray<NSString*>* filtered = [NSMutableArray array];
    for (NSString* part in parts) {
        if (part.length > 0) {
            [filtered addObject:part];
        }
    }
    return [filtered componentsJoinedByString:@" "];
}

static NSComparisonResult CompareTracksByFrameThenKey(TimedMediaMetaData* a, TimedMediaMetaData* b)
{
    NSNumber* frameA = a.frame ?: @0;
    NSNumber* frameB = b.frame ?: @0;
    NSComparisonResult frameResult = [frameA compare:frameB];
    if (frameResult != NSOrderedSame) {
        return frameResult;
    }
    NSString* artistA = NormalizeTrackKeyComponent(a.meta.artist ?: @"");
    NSString* artistB = NormalizeTrackKeyComponent(b.meta.artist ?: @"");
    NSComparisonResult artistResult = [artistA compare:artistB];
    if (artistResult != NSOrderedSame) {
        return artistResult;
    }
    NSString* titleA = NormalizeTrackKeyComponent(a.meta.title ?: @"");
    NSString* titleB = NormalizeTrackKeyComponent(b.meta.title ?: @"");
    NSComparisonResult titleResult = [titleA compare:titleB];
    if (titleResult != NSOrderedSame) {
        return titleResult;
    }
    NSString* rawArtistA = a.meta.artist ?: @"";
    NSString* rawArtistB = b.meta.artist ?: @"";
    NSComparisonResult rawArtistResult = [rawArtistA compare:rawArtistB];
    if (rawArtistResult != NSOrderedSame) {
        return rawArtistResult;
    }
    NSString* rawTitleA = a.meta.title ?: @"";
    NSString* rawTitleB = b.meta.title ?: @"";
    return [rawTitleA compare:rawTitleB];
}

static void WriteScoreLogLine(const char *line)
{
    if (line == NULL) {
        return;
    }
    static int fd = -1;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        fd = open("/tmp/refine_scores.log", O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd != -1) {
            char header[128];
            int written = snprintf(header, sizeof(header), "[ScoreV2] pid:%d\n", getpid());
            if (written > 0) {
                (void)write(fd, header, (size_t)written);
            }
        }
    });
    if (fd == -1) {
        return;
    }
    size_t len = strlen(line);
    if (len > 0) {
        (void)write(fd, line, len);
    }
}

typedef NSArray<TimedMediaMetaData*>* _Nonnull (^TracklistFilterBlock)(NSArray<TimedMediaMetaData*>* _Nonnull tracks,
                                                                       NSArray<TimedMediaMetaData*>* _Nonnull rawInput);

@interface TracklistFilterSpec : NSObject
@property (copy, nonatomic) NSString* name;
@property (copy, nonatomic) TracklistFilterBlock block;
+ (instancetype)specWithName:(NSString*)name block:(TracklistFilterBlock)block;
@end

@implementation TracklistFilterSpec
+ (instancetype)specWithName:(NSString*)name block:(TracklistFilterBlock)block
{
    TracklistFilterSpec* spec = [TracklistFilterSpec new];
    spec.name = name;
    spec.block = block;
    return spec;
}
@end

@implementation TotalIdentificationController (Refinement)

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
    NSArray<TimedMediaMetaData*>* input = [_identifieds copy];

    if (input.count == 0) {
        return @[];
    }

    if (_debugScoring) {
        [self logTracklist:input tag:@"Shazam" includeDuration:NO];
    }

    NSArray<TimedMediaMetaData*>* result = [self applyTracklistFiltersToInput:input];

    if (_debugScoring) {
        for (TimedMediaMetaData* t in result) {
            if (t.score == nil || t.confidence == nil) {
                NSLog(@"[Refine] missing score/conf frame:%@ artist:%@ title:%@ score:%@ confidence:%@",
                      t.frame, t.meta.artist ?: @"", t.meta.title ?: @"", t.score, t.confidence);
            }
        }
    }

    [self logTracklist:result tag:@"Final" includeDuration:YES];

    return result;
}

- (NSArray<TimedMediaMetaData*>*)applyTracklistFiltersToInput:(NSArray<TimedMediaMetaData*>*)input
{
    NSArray<TimedMediaMetaData*>* current = input;
    NSArray<TracklistFilterSpec*>* pipeline = [self refinementPipeline];
    for (TracklistFilterSpec* spec in pipeline) {
        if (_debugScoring) {
            NSLog(@"[Refine] filter:%@ in:%lu", spec.name, (unsigned long)current.count);
        }
        current = spec.block(current, input) ?: @[];
        if (_debugScoring) {
            NSUInteger nilScores = 0;
            for (TimedMediaMetaData* t in current) {
                if (t.score == nil) {
                    nilScores += 1;
                }
            }
            if (nilScores > 0) {
                NSLog(@"[Refine] filter:%@ nilScore:%lu", spec.name, (unsigned long)nilScores);
            }
            NSLog(@"[Refine] filter:%@ out:%lu", spec.name, (unsigned long)current.count);
        }
        if (current.count == 0) {
            break;
        }
    }
    return current ?: @[];
}

- (NSArray<TracklistFilterSpec*>*)refinementPipeline
{
    return @[
        [TracklistFilterSpec specWithName:@"aggregate" block:^NSArray<TimedMediaMetaData*>*(NSArray<TimedMediaMetaData*>* tracks, NSArray<TimedMediaMetaData*>* rawInput) {
            return [self aggregateIdentifieds:rawInput];
        }],
        [TracklistFilterSpec specWithName:@"score" block:^NSArray<TimedMediaMetaData*>*(NSArray<TimedMediaMetaData*>* tracks, NSArray<TimedMediaMetaData*>* rawInput) {
            return [self scoreTracks:tracks];
        }],
        [TracklistFilterSpec specWithName:@"mergeDuplicates" block:^NSArray<TimedMediaMetaData*>*(NSArray<TimedMediaMetaData*>* tracks, NSArray<TimedMediaMetaData*>* rawInput) {
            return [self mergeDuplicateTracks:tracks];
        }],
        [TracklistFilterSpec specWithName:@"resolveOverlaps" block:^NSArray<TimedMediaMetaData*>*(NSArray<TimedMediaMetaData*>* tracks, NSArray<TimedMediaMetaData*>* rawInput) {
            return [self resolveOverlapsInTracks:tracks];
        }],
        [TracklistFilterSpec specWithName:@"finalFilter" block:^NSArray<TimedMediaMetaData*>*(NSArray<TimedMediaMetaData*>* tracks, NSArray<TimedMediaMetaData*>* rawInput) {
            return [self applyFinalTrackFilters:tracks];
        }],
        [TracklistFilterSpec specWithName:@"intervalSchedule" block:^NSArray<TimedMediaMetaData*>*(NSArray<TimedMediaMetaData*>* tracks, NSArray<TimedMediaMetaData*>* rawInput) {
            return [self applyIntervalScheduleToTracks:tracks];
        }],
        [TracklistFilterSpec specWithName:@"dedupe" block:^NSArray<TimedMediaMetaData*>*(NSArray<TimedMediaMetaData*>* tracks, NSArray<TimedMediaMetaData*>* rawInput) {
            return [self dedupeTracksByKey:tracks];
        }],
    ];
}

- (void)logTracklist:(NSArray<TimedMediaMetaData*>*)tracks tag:(NSString*)tag includeDuration:(BOOL)includeDuration
{
    if (!_debugScoring) {
        return;
    }
    if ([tag isEqualToString:@"Shazam"]) {
        double rate = self->_sample != nil ? self->_sample.sampleFormat.rate : 0.0;
        unsigned long long frames = self->_sample != nil ? self->_sample.frames : 0;
        double signatureWindow = self.signatureWindowSeconds > 0.0 ? self.signatureWindowSeconds : 8.0;
        double signatureWindowMax = self.signatureWindowMaxSeconds > 0.0 ? self.signatureWindowMaxSeconds : signatureWindow;
        NSLog(@"[InputMeta] sampleRate:%.1f hopSize:%u signatureWindow:%.1fs maxSignatureWindow:%.1fs skipRefinement:%d frames:%llu",
              rate,
              (unsigned int)self->_hopSize,
              signatureWindow,
              signatureWindowMax,
              self.skipRefinement ? 1 : 0,
              frames);
    }
    for (TimedMediaMetaData* t in tracks) {
        if (includeDuration) {
            double durationSeconds = [self estimatedDurationForTrack:t nextTrack:nil];
            NSLog(@"[%@] frame:%@ artist:%@ title:%@ duration:%.2fs score:%.3f confidence:%@",
                  tag,
                  t.frame,
                  t.meta.artist ?: @"",
                  t.meta.title ?: @"",
                  durationSeconds,
                  t.score.doubleValue,
                  t.confidence);
        } else {
            NSLog(@"[%@] frame:%@ artist:%@ title:%@ score:%.3f confidence:%@",
                  tag,
                  t.frame,
                  t.meta.artist ?: @"",
                  t.meta.title ?: @"",
                  t.score.doubleValue,
                  t.confidence);
        }
    }
}

- (NSArray<TimedMediaMetaData*>*)aggregateIdentifieds:(NSArray<TimedMediaMetaData*>*)input
{
    double sampleRate = (double)self->_sample.sampleFormat.rate;
    unsigned long long clusterGapFrames = (unsigned long long)(sampleRate * 240.0);
    NSInteger minSupport = self.skipRefinement ? 1 : 2;

    NSMutableDictionary<NSString*, NSMutableArray<TimedMediaMetaData*>*>* buckets = [NSMutableDictionary dictionary];
    for (TimedMediaMetaData* t in input) {
        if (t.meta.title.length == 0 || t.frame == nil) {
            continue;
        }
        NSString* titleKey = NormalizeTrackKeyComponent(t.meta.title);
        if (titleKey.length == 0) {
            continue;
        }
        NSString* artistKey = NormalizeTrackKeyComponent(t.meta.artist ?: @"");
        NSString* key = [NSString stringWithFormat:@"%@ - %@", artistKey, titleKey];
        NSMutableArray<TimedMediaMetaData*>* list = buckets[key];
        if (list == nil) {
            list = [NSMutableArray array];
            buckets[key] = list;
        }
        [list addObject:t];
    }

    if (buckets.count == 0) {
        if (_debugScoring) {
            NSLog(@"[Refine] aggregate: no candidates after normalization");
        }
        return @[];
    }

    NSMutableArray<TimedMediaMetaData*>* result = [NSMutableArray array];
    for (NSString* key in buckets) {
        NSMutableArray<TimedMediaMetaData*>* list = buckets[key];
        [list sortUsingComparator:^NSComparisonResult(TimedMediaMetaData* a, TimedMediaMetaData* b) {
            return CompareTracksByFrameThenKey(a, b);
        }];

        TimedMediaMetaData* clusterFirst = nil;
        unsigned long long clusterLast = 0;
        NSInteger clusterCount = 0;
        for (TimedMediaMetaData* t in list) {
            unsigned long long frame = t.frame.unsignedLongLongValue;
            if (clusterFirst == nil) {
                clusterFirst = t;
                clusterLast = frame;
                clusterCount = 1;
                continue;
            }
            if (frame - clusterLast <= clusterGapFrames) {
                clusterLast = frame;
                clusterCount += 1;
            } else {
                if (clusterCount >= minSupport) {
                    TimedMediaMetaData* agg = [TimedMediaMetaData new];
                    agg.meta = clusterFirst.meta;
                    agg.frame = clusterFirst.frame;
                    agg.endFrame = @(clusterLast);
                    agg.supportCount = @(clusterCount);
                    agg.confidence = @(clusterCount);
                    [result addObject:agg];
                }
                clusterFirst = t;
                clusterLast = frame;
                clusterCount = 1;
            }
        }
        if (clusterFirst != nil && clusterCount >= minSupport) {
            TimedMediaMetaData* agg = [TimedMediaMetaData new];
            agg.meta = clusterFirst.meta;
            agg.frame = clusterFirst.frame;
            agg.endFrame = @(clusterLast);
            agg.supportCount = @(clusterCount);
            agg.confidence = @(clusterCount);
            [result addObject:agg];
        }
    }

    if (_debugScoring) {
        NSLog(@"[Refine] aggregate: keys:%lu kept:%lu minSupport:%ld",
              (unsigned long)buckets.count,
              (unsigned long)result.count,
              (long)minSupport);
        NSArray<TimedMediaMetaData*>* yotto = buckets[@"yotto seat 11"];
        if (yotto != nil && yotto.count > 0) {
            TimedMediaMetaData* first = yotto.firstObject;
            TimedMediaMetaData* last = yotto.lastObject;
            NSLog(@"[Refine] aggregate: key:yotto seat 11 count:%lu frame:%@ last:%@",
                  (unsigned long)yotto.count,
                  first.frame ?: @"",
                  last.frame ?: @"");
        } else {
            NSLog(@"[Refine] aggregate: key:yotto seat 11 missing");
        }
        __block NSUInteger logged = 0;
        [buckets enumerateKeysAndObjectsUsingBlock:^(NSString* key, NSArray<TimedMediaMetaData*>* list, BOOL* stop) {
            if (logged >= 8) { *stop = YES; return; }
            NSNumber* frame = list.count > 0 ? ((TimedMediaMetaData*)list[0]).frame : nil;
            NSLog(@"[Refine] aggregate: key:%@ count:%lu frame:%@", key, (unsigned long)list.count, frame ?: @"");
            logged += 1;
        }];
    }

    return result;
}

- (NSArray<TimedMediaMetaData*>*)scoreTracks:(NSArray<TimedMediaMetaData*>*)tracks
{
    NSMutableArray<TimedMediaMetaData*>* sorted = [tracks mutableCopy];
    [sorted sortUsingComparator:^NSComparisonResult(TimedMediaMetaData* a, TimedMediaMetaData* b) {
        return CompareTracksByFrameThenKey(a, b);
    }];

    // After sorting, recompute duration/producer-based scores using neighbors and reflect into confidence.
    NSUInteger missingScore = 0;
    for (NSUInteger i = 0; i < sorted.count; i++) {
        TimedMediaMetaData* current = sorted[i];
        // Find the next track with a strictly greater frame to estimate duration.
        TimedMediaMetaData* next = nil;
        for (NSUInteger j = i + 1; j < sorted.count; j++) {
            if (sorted[j].frame.unsignedLongLongValue > current.frame.unsignedLongLongValue) {
                next = sorted[j];
                break;
            }
        }
        double s = [self scoreForTrack:current nextTrack:next];
        current.score = @(s);
        current.confidence = @(s);
        if (current.score == nil) {
            missingScore += 1;
        }
        if (_debugScoring) {
            NSString* title = current.meta.title ?: @"";
            NSString* artist = current.meta.artist ?: @"";
            double durationSeconds = [self estimatedDurationForTrack:current nextTrack:next];
            const char* frameC = current.frame != nil ? current.frame.stringValue.UTF8String : "<nil>";
            const char* artistC = artist.length > 0 ? artist.UTF8String : "";
            const char* titleC = title.length > 0 ? title.UTF8String : "";
            const char* scoreC = current.score != nil ? current.score.stringValue.UTF8String : "<nil>";
            const char* confC = current.confidence != nil ? current.confidence.stringValue.UTF8String : "<nil>";
            const char* supportC = current.supportCount != nil ? current.supportCount.stringValue.UTF8String : "<nil>";
            char line[1024];
            int written = snprintf(line,
                                   sizeof(line),
                                   "[ScoreV2:scoreTracks] frame:%s artist:%s title:%s duration:%.2fs raw:%.3f stored:%s conf:%s support:%s\n",
                                   frameC,
                                   artistC,
                                   titleC,
                                   durationSeconds,
                                   s,
                                   scoreC,
                                   confC,
                                   supportC);
            if (written > 0) {
                WriteScoreLogLine(line);
            }
            if (current.score == nil || current.confidence == nil) {
                NSLog(@"[ScoreV2] missing assignment frame:%@", current.frame);
            }
        }
    }
    if (_debugScoring && missingScore > 0) {
        NSLog(@"[Score] missing score on %lu tracks", (unsigned long)missingScore);
    }

    return sorted;
}

- (NSArray<TimedMediaMetaData*>*)pruneLowEvidenceTracks:(NSArray<TimedMediaMetaData*>*)tracks
{
    // Early pruning of low-evidence outliers: single hits that are extremely low score.
    return [tracks filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(TimedMediaMetaData *t, NSDictionary<NSString *,id> *bindings) {
        double s = t.score != nil ? t.score.doubleValue : 0.0;

        // Drop anything below the configured score floor unless it has repeat support.
        NSInteger support = t.supportCount != nil ? t.supportCount.integerValue : 0;
        if (s < self->_minScoreThreshold && support < 2) { return NO; }
        return YES;
    }]];
}

- (NSArray<TimedMediaMetaData*>*)mergeDuplicateTracks:(NSArray<TimedMediaMetaData*>*)tracks
{
    // Merge near-duplicates (same/related track within a small time window), keeping the higher-scoring one.
    double windowFrames = _duplicateMergeWindowSeconds * (double)self->_sample.sampleFormat.rate;
    NSMutableArray<TimedMediaMetaData*>* pruned = [NSMutableArray array];
    for (NSUInteger i = 0; i < tracks.count; i++) {
        TimedMediaMetaData* current = tracks[i];
        for (NSUInteger j = i + 1; j < tracks.count; j++) {
            TimedMediaMetaData* other = tracks[j];
            if (other.frame.unsignedLongLongValue - current.frame.unsignedLongLongValue > windowFrames) {
                break;
            }
            if ([self isSimilarTrack:current other:other]) {
                TimedMediaMetaData* winner = current.score.doubleValue >= other.score.doubleValue ? current : other;
                TimedMediaMetaData* loser = (winner == current) ? other : current;
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

    return pruned;
}

- (NSArray<TimedMediaMetaData*>*)resolveOverlapsInTracks:(NSArray<TimedMediaMetaData*>*)tracks
{
    // Enforce a simple non-overlap rule: walk in frame order and keep the higher-scoring
    // track when two spans would overlap. We always favor the higher score, regardless
    // of order, so strong tracks push out weaker overlapping candidates. Duration is
    // estimated from either metadata, the span of repeated detections, or gap to the next track.
    NSMutableArray<TimedMediaMetaData*>* nonOverlapping = [NSMutableArray array];
    TimedMediaMetaData* lastKept = nil;
    unsigned long long lastEnd = 0;
    double lastScore = 0.0;
    NSInteger lastSupport = 0;
    double sampleRate = (double)self->_sample.sampleFormat.rate;
    unsigned long long changeoverFrames = (unsigned long long)(sampleRate * 90.0);
    for (NSUInteger i = 0; i < tracks.count; i++) {
        TimedMediaMetaData* current = tracks[i];
        TimedMediaMetaData* lookahead = (i + 1 < tracks.count) ? tracks[i + 1] : nil;
        unsigned long long start = current.frame != nil ? current.frame.unsignedLongLongValue : 0;
        double durationSeconds = [self estimatedDurationForTrack:current nextTrack:lookahead];
        NSInteger support = current.supportCount != nil ? current.supportCount.integerValue : 0;
        if (support < 3 && durationSeconds > 180.0) {
            durationSeconds = 180.0;
        }
        unsigned long long end = start;
        if (durationSeconds > 0.0 && sampleRate > 0.0) {
            end = start + (unsigned long long)(durationSeconds * sampleRate);
        }
        double score = current.score != nil ? current.score.doubleValue : 0.0;

        if (nonOverlapping.count == 0) {
            [nonOverlapping addObject:current];
            lastKept = current;
            lastEnd = end;
            lastScore = score;
            lastSupport = support;
            continue;
        }

        if (start < lastEnd) {
            // Overlap: keep the higher-scoring of the two regardless of order.
            BOOL lastIsUnknown = IsUnknownTrack(lastKept);
            BOOL currentIsUnknown = IsUnknownTrack(current);

            // Prefer real tracks over "unknown" filler regardless of score.
            if (lastIsUnknown && !currentIsUnknown) {
                if (_debugScoring) {
                    NSLog(@"[Refine] overlap: replacing unknown at %@ with %@ %@ (score %.3f)",
                          lastKept.frame, current.meta.artist ?: @"", current.meta.title ?: @"", score);
                }
                [nonOverlapping removeLastObject];
                [nonOverlapping addObject:current];
                lastKept = current;
                lastEnd = end;
                lastScore = score;
                lastSupport = support;
            } else if (!lastIsUnknown && currentIsUnknown) {
                if (_debugScoring) {
                    NSLog(@"[Refine] overlap: keeping %@ %@, dropping unknown at %@",
                          lastKept.meta.artist ?: @"", lastKept.meta.title ?: @"", current.frame);
                }
                // Drop the unknown overlap; keep the real track already kept.
                continue;
            } else if (lastKept != nil && start > lastKept.frame.unsignedLongLongValue &&
                       (start - lastKept.frame.unsignedLongLongValue) >= changeoverFrames) {
                NSInteger minSupport = MAX(2, (NSInteger)ceil((double)lastSupport * 0.4));
                if (support >= minSupport) {
                    if (_debugScoring) {
                        NSLog(@"[Refine] overlap: changeover %@ %@ -> %@ %@ (support %ld >= %ld)",
                              lastKept.meta.artist ?: @"", lastKept.meta.title ?: @"",
                              current.meta.artist ?: @"", current.meta.title ?: @"",
                              (long)support, (long)minSupport);
                    }
                    [nonOverlapping removeLastObject];
                    [nonOverlapping addObject:current];
                    lastKept = current;
                    lastEnd = end;
                    lastScore = score;
                    lastSupport = support;
                } else {
                    if (_debugScoring) {
                        NSLog(@"[Refine] overlap: changeover blocked for %@ %@ (support %ld < %ld)",
                              current.meta.artist ?: @"", current.meta.title ?: @"",
                              (long)support, (long)minSupport);
                    }
                    continue;
                }
            } else if (score > lastScore) {
                if (_debugScoring) {
                    NSLog(@"[Refine] overlap: replacing %@ %@ with %@ %@ (%.3f > %.3f)",
                          lastKept.meta.artist ?: @"", lastKept.meta.title ?: @"",
                          current.meta.artist ?: @"", current.meta.title ?: @"",
                          score, lastScore);
                }
                [nonOverlapping removeLastObject];
                [nonOverlapping addObject:current];
                lastKept = current;
                lastEnd = end;
                lastScore = score;
                lastSupport = support;
            } else {
                if (_debugScoring) {
                    NSLog(@"[Refine] overlap: keeping %@ %@ (%.3f >= %.3f), dropping %@ %@",
                          lastKept.meta.artist ?: @"", lastKept.meta.title ?: @"",
                          lastScore, score,
                          current.meta.artist ?: @"", current.meta.title ?: @"");
                }
                // Keep previous; drop current.
            }
        } else {
            [nonOverlapping addObject:current];
            lastKept = current;
            lastEnd = end;
            lastScore = score;
            lastSupport = support;
        }
    }

    return nonOverlapping;
}

- (NSArray<TimedMediaMetaData*>*)applyFinalTrackFilters:(NSArray<TimedMediaMetaData*>*)tracks
{
    // Apply the short/low filter late, after overlaps and gap fill.
    NSMutableArray<TimedMediaMetaData*>* filtered = [NSMutableArray array];
    for (NSUInteger i = 0; i < tracks.count; i++) {
        TimedMediaMetaData* current = tracks[i];
        TimedMediaMetaData* next = (i + 1 < tracks.count) ? tracks[i + 1] : nil;
        double durationSeconds = [self estimatedDurationForTrack:current nextTrack:next];
        double s = current.score != nil ? current.score.doubleValue : 0.0;
        NSInteger support = current.supportCount != nil ? current.supportCount.integerValue : 0;
        double spanSeconds = 0.0;
        if (current.endFrame != nil && current.frame != nil && current.endFrame.unsignedLongLongValue > current.frame.unsignedLongLongValue) {
            double frameSpan = (double)(current.endFrame.unsignedLongLongValue - current.frame.unsignedLongLongValue);
            spanSeconds = frameSpan / (double)self->_sample.sampleFormat.rate;
        }

        // For single-hit tracks, be stricter on short durations unless the score is strong.
        if (support <= 1 && durationSeconds > 0.0 && durationSeconds < 90.0 && s < 3.2) {
            if (_debugScoring) {
                NSLog(@"[Score] dropping short single-hit at frame %@ (duration %.2fs score %.3f)", current.frame, durationSeconds, s);
            }
            continue;
        }
        if (support == 4 && spanSeconds > 0.0 && spanSeconds < 30.0) {
            if (_debugScoring) {
                NSLog(@"[Score] dropping tight four-hit span at frame %@ (span %.2fs)", current.frame, spanSeconds);
            }
            continue;
        }
        if (support == 2) {
            if (spanSeconds <= 0.0) {
                if (_debugScoring) {
                    NSLog(@"[Score] dropping zero-span two-hit at frame %@", current.frame);
                }
                continue;
            }
            if (durationSeconds >= 90.0) {
                if (_debugScoring) {
                    NSLog(@"[Score] dropping long two-hit at frame %@ (duration %.2fs)", current.frame, durationSeconds);
                }
                continue;
            }
        }
        if (support > 1 && support < 8) {
            double avgGap = (spanSeconds > 0.0 && support > 1) ? (spanSeconds / (double)(support - 1)) : 0.0;
            if (avgGap > 30.0) {
                if (_debugScoring) {
                    NSLog(@"[Score] dropping sparse hit at frame %@ (avgGap %.2fs support %ld)", current.frame, avgGap, (long)support);
                }
                continue;
            }
        }
        const double shortCutoffSeconds = 90.0; // ~1.5 minutes
        if (s < _minScoreThreshold && durationSeconds > 0.0 && durationSeconds < shortCutoffSeconds) {
            if (_debugScoring) {
                NSLog(@"[Score] dropping low-score short candidate at frame %@ (duration %.2fs score %.3f)", current.frame, durationSeconds, s);
            }
            continue;
        }

        [filtered addObject:current];
    }

    return filtered;
}

- (NSArray<TimedMediaMetaData*>*)applyIntervalScheduleToTracks:(NSArray<TimedMediaMetaData*>*)tracks
{
    if (tracks.count == 0) {
        return tracks;
    }
    NSMutableArray<TimedMediaMetaData*>* sorted = [tracks mutableCopy];
    [sorted sortUsingComparator:^NSComparisonResult(TimedMediaMetaData* a, TimedMediaMetaData* b) {
        return CompareTracksByFrameThenKey(a, b);
    }];

    const double sampleRate = (double)self->_sample.sampleFormat.rate;
    const double minSeconds = 120.0;

    NSUInteger count = sorted.count;
    NSMutableArray<NSNumber*>* starts = [NSMutableArray arrayWithCapacity:count];
    NSMutableArray<NSNumber*>* ends = [NSMutableArray arrayWithCapacity:count];

    for (NSUInteger i = 0; i < count; i++) {
        TimedMediaMetaData* current = sorted[i];
        TimedMediaMetaData* next = (i + 1 < count) ? sorted[i + 1] : nil;
        unsigned long long start = current.frame != nil ? current.frame.unsignedLongLongValue : 0;
        double durationSeconds = 0.0;
        if (current.endFrame != nil && current.frame != nil &&
            current.endFrame.unsignedLongLongValue > current.frame.unsignedLongLongValue) {
            unsigned long long spanFrames = current.endFrame.unsignedLongLongValue - current.frame.unsignedLongLongValue;
            durationSeconds = (sampleRate > 0.0) ? ((double)spanFrames / sampleRate) : 0.0;
        }
        if (durationSeconds <= 0.0) {
            durationSeconds = [self estimatedDurationForTrack:current nextTrack:next];
        }
        if (durationSeconds <= 0.0) {
            durationSeconds = minSeconds;
        }
        unsigned long long end = start;
        if (sampleRate > 0.0 && durationSeconds > 0.0) {
            end = start + (unsigned long long)(durationSeconds * sampleRate);
        }
        [starts addObject:@(start)];
        [ends addObject:@(end)];
    }

    NSMutableArray<NSNumber*>* p = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger j = 0; j < count; j++) {
        unsigned long long start = starts[j].unsignedLongLongValue;
        NSInteger last = -1;
        for (NSInteger i = (NSInteger)j - 1; i >= 0; i--) {
            if (ends[i].unsignedLongLongValue <= start) {
                last = i;
                break;
            }
        }
        [p addObject:@(last)];
    }

    NSMutableArray<NSNumber*>* dp = [NSMutableArray arrayWithCapacity:count];
    NSMutableArray<NSNumber*>* choose = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger j = 0; j < count; j++) {
        double score = sorted[j].score != nil ? sorted[j].score.doubleValue : 0.0;
        NSInteger prev = p[j].integerValue;
        double incl = score + (prev >= 0 ? dp[prev].doubleValue : 0.0);
        double excl = (j > 0) ? dp[j - 1].doubleValue : 0.0;
        if (incl >= excl) {
            [dp addObject:@(incl)];
            [choose addObject:@(YES)];
        } else {
            [dp addObject:@(excl)];
            [choose addObject:@(NO)];
        }
    }

    NSMutableArray<TimedMediaMetaData*>* selected = [NSMutableArray array];
    NSInteger j = (NSInteger)count - 1;
    while (j >= 0) {
        if (choose[j].boolValue) {
            [selected addObject:sorted[j]];
            j = p[j].integerValue;
        } else {
            j -= 1;
        }
    }
    NSArray<TimedMediaMetaData*>* reversed = [[selected reverseObjectEnumerator] allObjects];
    return reversed;
}

- (NSArray<TimedMediaMetaData*>*)dedupeTracksByKey:(NSArray<TimedMediaMetaData*>*)tracks
{
    if (tracks.count == 0) {
        return tracks;
    }
    NSMutableDictionary<NSString*, TimedMediaMetaData*>* best = [NSMutableDictionary dictionary];
    NSMutableArray<TimedMediaMetaData*>* passthrough = [NSMutableArray array];

    for (TimedMediaMetaData* t in tracks) {
        NSString* titleKey = NormalizeTrackKeyComponent(t.meta.title);
        if (titleKey.length == 0) {
            [passthrough addObject:t];
            continue;
        }
        NSString* artistKey = NormalizeTrackKeyComponent(t.meta.artist);
        NSString* key = [NSString stringWithFormat:@"%@|%@", artistKey, titleKey];
        TimedMediaMetaData* current = best[key];
        if (current == nil) {
            best[key] = t;
            continue;
        }
        double scoreA = t.score != nil ? t.score.doubleValue : 0.0;
        double scoreB = current.score != nil ? current.score.doubleValue : 0.0;
        NSInteger supportA = t.supportCount != nil ? t.supportCount.integerValue : 0;
        NSInteger supportB = current.supportCount != nil ? current.supportCount.integerValue : 0;
        unsigned long long frameA = t.frame != nil ? t.frame.unsignedLongLongValue : 0;
        unsigned long long frameB = current.frame != nil ? current.frame.unsignedLongLongValue : 0;
        BOOL replace = NO;
        if (scoreA > scoreB) {
            replace = YES;
        } else if (scoreA == scoreB && supportA > supportB) {
            replace = YES;
        } else if (scoreA == scoreB && supportA == supportB && frameA < frameB) {
            replace = YES;
        }
        if (replace) {
            best[key] = t;
        }
    }

    NSMutableArray<TimedMediaMetaData*>* result = [NSMutableArray arrayWithArray:passthrough];
    [result addObjectsFromArray:best.allValues];
    [result sortUsingComparator:^NSComparisonResult(TimedMediaMetaData* a, TimedMediaMetaData* b) {
        return CompareTracksByFrameThenKey(a, b);
    }];
    return result;
}

- (double)scoreForTrack:(TimedMediaMetaData*)track nextTrack:(TimedMediaMetaData* _Nullable)next
{
    // Base score starts from support or the prior confidence.
    // We intentionally let support scale freely (no cap) so a strongly repeated hit
    // can dominate and push out unlikely, short-lived candidates.
    double base = 1.0;
    if (track.supportCount != nil) {
        // Favor repeated hits more strongly; sqrt keeps growth under control.
        double s = MAX(1.0, track.supportCount.doubleValue);
        base = MIN(14.0, 1.0 + sqrt(s) * 4.0); // ranges from ~5 (1 hit) up to 14
    } else if (track.confidence != nil) {
        base = track.confidence.doubleValue;
    }

    // Duration heuristic: prefer 4–8 minutes. Estimate duration from metadata if present, otherwise from spacing to next track.
    double durationSeconds = [self estimatedDurationForTrack:track nextTrack:next];

    double durationScore = 1.0;
    if (durationSeconds <= 0.0) {
        // Unknown duration: keep it viable; rely more on support count.
        durationScore = 0.70;
    } else if (durationSeconds < 90.0) {
        // Very short (<1.5min): small penalty.
        double ratio = durationSeconds / _idealTrackMinSeconds; // tiny number
        durationScore = MAX(0.60, 0.60 + 0.40 * ratio);
    } else if (durationSeconds >= _idealTrackMinSeconds && durationSeconds <= _idealTrackMaxSeconds) {
        // Ideal window: modest reward.
        durationScore = 1.20;
    } else if (durationSeconds < _idealTrackMinSeconds) {
        // Short: gentler quadratic falloff; floor at 0.60.
        double ratio = durationSeconds / _idealTrackMinSeconds; // 0..1
        durationScore = MAX(0.60, 0.9 * ratio * ratio);
    } else {
        // Penalize long tracks; floor at 0.40.
        double ratio = _idealTrackMaxSeconds / durationSeconds;
        durationScore = MAX(0.40, 0.9 * ratio);
    }

    // De-weight duration so repetition dominates.
    double score = base * (0.4 + 0.6 * durationScore);

    // Producer/artist bonus: if the reference artist appears in the detected artist or title, boost strongly.
    NSString* refArtist = _referenceArtist;
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
    NSString* (^normKey)(TimedMediaMetaData*) = ^NSString* (TimedMediaMetaData* t) {
        NSString* artist = t.meta.artist ?: @"";
        NSString* title = t.meta.title ?: @"";
        NSString* key = [NSString stringWithFormat:@"%@ — %@", artist, title];
        key = [[key precomposedStringWithCanonicalMapping] lowercaseString];
        key = [key stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return key;
    };

    NSMutableDictionary<NSString*, NSMutableDictionary*>* supportAgg = [NSMutableDictionary dictionary];
    for (TimedMediaMetaData* t in input) {
        if (t.meta.title.length == 0 || t.frame == nil) {
            continue;
        }
        NSString* k = normKey(t);
        if (k.length == 0) {
            continue;
        }
        NSMutableDictionary* entry = supportAgg[k];
        if (entry == nil) {
            entry = [@{@"frame": t.frame,
                       @"count": @(1)} mutableCopy];
            supportAgg[k] = entry;
        } else {
            entry[@"count"] = @([entry[@"count"] integerValue] + 1);
            NSNumber* existingFrame = entry[@"frame"];
            if (t.frame.unsignedLongLongValue < existingFrame.unsignedLongLongValue) {
                entry[@"frame"] = t.frame;
            }
        }
    }

    NSMutableArray<TimedMediaMetaData*>* aggregatedSupport = [NSMutableArray array];
    for (NSString* key in supportAgg) {
        NSDictionary* entry = supportAgg[key];
        NSInteger count = [entry[@"count"] integerValue];
        if (count < 2) {
            continue;
        }
        TimedMediaMetaData* t = [TimedMediaMetaData new];
        t.frame = entry[@"frame"];
        t.supportCount = entry[@"count"];
        [aggregatedSupport addObject:t];
    }

    NSMutableArray<TimedMediaMetaData*>* sortedTracks = [tracks mutableCopy];
    [sortedTracks sortUsingComparator:^NSComparisonResult(TimedMediaMetaData* a, TimedMediaMetaData* b) {
        return CompareTracksByFrameThenKey(a, b);
    }];

    NSMutableArray<TimedMediaMetaData*>* augmented = [sortedTracks mutableCopy];
    double sampleRate = (double)self->_sample.sampleFormat.rate;
    const double gapMinSeconds = 600.0;
    const NSInteger minSupportThreshold = 3;

    for (NSUInteger i = 0; i + 1 < sortedTracks.count; i++) {
        unsigned long long gapStart = sortedTracks[i].frame.unsignedLongLongValue;
        unsigned long long gapEnd = sortedTracks[i + 1].frame.unsignedLongLongValue;
        if (gapEnd <= gapStart) {
            continue;
        }
        double gapSeconds = sampleRate > 0.0 ? ((double)(gapEnd - gapStart) / sampleRate) : 0.0;
        if (gapSeconds < gapMinSeconds) {
            continue;
        }
        NSInteger maxSupport = 0;
        for (TimedMediaMetaData* t in aggregatedSupport) {
            unsigned long long f = t.frame != nil ? t.frame.unsignedLongLongValue : 0;
            if (f > gapStart && f < gapEnd) {
                NSInteger support = t.supportCount != nil ? t.supportCount.integerValue : 0;
                if (support > maxSupport) {
                    maxSupport = support;
                }
            }
        }
        if (maxSupport >= minSupportThreshold) {
            if (_debugScoring) {
                NSLog(@"[Refine] unknown gap skip start:%llu end:%llu gap:%.2fs maxSupport:%ld",
                      gapStart, gapEnd, gapSeconds, (long)maxSupport);
            }
            continue;
        }

        unsigned long long mid = gapStart + (gapEnd - gapStart) / 2;
        if (_debugScoring) {
            NSLog(@"[Refine] unknown gap insert start:%llu end:%llu mid:%llu gap:%.2fs maxSupport:%ld",
                  gapStart, gapEnd, mid, gapSeconds, (long)maxSupport);
        }
        TimedMediaMetaData* unknown = [TimedMediaMetaData unknownTrackAtFrame:@(mid)];
        unknown.supportCount = @(0);
        unknown.score = @(0.0);
        unknown.confidence = @(0.0);
        [augmented addObject:unknown];
    }

    [augmented sortUsingComparator:^NSComparisonResult(TimedMediaMetaData* a, TimedMediaMetaData* b) {
        return CompareTracksByFrameThenKey(a, b);
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

@end

NS_ASSUME_NONNULL_END
