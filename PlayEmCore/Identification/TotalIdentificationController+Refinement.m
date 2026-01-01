//
//  TotalIdentificationController+Refinement.m
//  PlayEm
//
//  Created by Till Toenshoff on 12/26/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

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

    [self logTracklist:input tag:@"Input" includeDuration:NO];

    NSArray<TimedMediaMetaData*>* result = [self applyTracklistFiltersToInput:input];

    [self logTracklist:result tag:@"Final" includeDuration:YES];

    return result;
}

- (NSArray<TimedMediaMetaData*>*)applyTracklistFiltersToInput:(NSArray<TimedMediaMetaData*>*)input
{
    NSArray<TimedMediaMetaData*>* current = input;
    NSArray<TracklistFilterSpec*>* pipeline = [self refinementPipeline];
    for (TracklistFilterSpec* spec in pipeline) {
        current = spec.block(current, input) ?: @[];
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
        [TracklistFilterSpec specWithName:@"pruneLowEvidence" block:^NSArray<TimedMediaMetaData*>*(NSArray<TimedMediaMetaData*>* tracks, NSArray<TimedMediaMetaData*>* rawInput) {
            return [self pruneLowEvidenceTracks:tracks];
        }],
        [TracklistFilterSpec specWithName:@"mergeDuplicates" block:^NSArray<TimedMediaMetaData*>*(NSArray<TimedMediaMetaData*>* tracks, NSArray<TimedMediaMetaData*>* rawInput) {
            return [self mergeDuplicateTracks:tracks];
        }],
        [TracklistFilterSpec specWithName:@"resolveOverlaps" block:^NSArray<TimedMediaMetaData*>*(NSArray<TimedMediaMetaData*>* tracks, NSArray<TimedMediaMetaData*>* rawInput) {
            return [self resolveOverlapsInTracks:tracks];
        }],
        [TracklistFilterSpec specWithName:@"fillUnknownGaps" block:^NSArray<TimedMediaMetaData*>*(NSArray<TimedMediaMetaData*>* tracks, NSArray<TimedMediaMetaData*>* rawInput) {
            return [self fillGapsWithUnknownsIn:tracks rawInput:rawInput];
        }],
        [TracklistFilterSpec specWithName:@"finalFilter" block:^NSArray<TimedMediaMetaData*>*(NSArray<TimedMediaMetaData*>* tracks, NSArray<TimedMediaMetaData*>* rawInput) {
            return [self applyFinalTrackFilters:tracks];
        }],
    ];
}

- (void)logTracklist:(NSArray<TimedMediaMetaData*>*)tracks tag:(NSString*)tag includeDuration:(BOOL)includeDuration
{
    if (!_debugScoring) {
        return;
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

    return result;
}

- (NSArray<TimedMediaMetaData*>*)scoreTracks:(NSArray<TimedMediaMetaData*>*)tracks
{
    NSMutableArray<TimedMediaMetaData*>* sorted = [tracks mutableCopy];
    [sorted sortUsingComparator:^NSComparisonResult(TimedMediaMetaData* a, TimedMediaMetaData* b) {
        return [a.frame compare:b.frame];
    }];

    // After sorting, recompute duration/producer-based scores using neighbors and reflect into confidence.
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
        if (self.debugScoring) {
            NSString* title = current.meta.title ?: @"";
            NSString* artist = current.meta.artist ?: @"";
            double durationSeconds = [self estimatedDurationForTrack:current nextTrack:next];
            NSLog(@"[Score] frame:%@ artist:%@ title:%@ duration:%.2fs score:%.3f confidence:%@", current.frame, artist, title, durationSeconds, s, current.confidence);
        }
    }

    return sorted;
}

- (NSArray<TimedMediaMetaData*>*)pruneLowEvidenceTracks:(NSArray<TimedMediaMetaData*>*)tracks
{
    // Early pruning of low-evidence outliers: single hits that are either
    // extremely low score or unrealistically long.
    const double extremelyLongSeconds = _idealTrackMaxSeconds * 2.0; // ~24 minutes
    return [tracks filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(TimedMediaMetaData *t, NSDictionary<NSString *,id> *bindings) {
        double s = t.score != nil ? t.score.doubleValue : 0.0;
        NSInteger support = t.supportCount != nil ? t.supportCount.integerValue : 0;
        double durationSeconds = [self estimatedDurationForTrack:t nextTrack:nil];

        // Drop anything below the configured score floor.
        if (s < self->_minScoreThreshold) { return NO; }

        // For single-hit candidates, still discard absurdly long spans (likely noise).
        if (support <= 1 && durationSeconds > extremelyLongSeconds) { return NO; }
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
    for (NSUInteger i = 0; i < tracks.count; i++) {
        TimedMediaMetaData* current = tracks[i];
        TimedMediaMetaData* lookahead = (i + 1 < tracks.count) ? tracks[i + 1] : nil;
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
        const double shortCutoffSeconds = 90.0; // ~1.5 minutes
        if (s < _minScoreThreshold && durationSeconds > 0.0 && durationSeconds < shortCutoffSeconds) {
            if (_debugScoring) {
                NSLog(@"[Score] dropping low-score short candidate at frame %@ (duration %.2fs score %.3f)", current.frame, durationSeconds, s);
            }
            continue;
        }

        // If a candidate made it this far but still has no meaningful score, drop it unless it is an "unknown" gap filler.
        BOOL isUnknown = IsUnknownTrack(current);
        const double minNonUnknownScore = 0.05; // never keep non-unknowns with near-zero score
        double keepThreshold = MAX(minNonUnknownScore, _minScoreThreshold);
        if (!isUnknown && s <= keepThreshold) {
            if (_debugScoring) {
                NSLog(@"[Score] dropping zero/near-zero score candidate at frame %@ (score %.3f)", current.frame, s);
            }
            continue;
        }

        [filtered addObject:current];
    }

    return filtered;
}

- (double)scoreForTrack:(TimedMediaMetaData*)track nextTrack:(TimedMediaMetaData* _Nullable)next
{
    // Base score starts from support or the prior confidence.
    // We intentionally let support scale freely (no cap) so a strongly repeated hit
    // can dominate and push out unlikely, short-lived candidates.
    double base = 1.0;
    if (track.supportCount != nil) {
        // Dampen runaway scores from many repeated hits: sqrt keeps a bonus but
        // prevents very chatty segments from dwarfing everything else.
        double s = MAX(1.0, track.supportCount.doubleValue);
        base = MIN(8.0, 1.0 + sqrt(s) * 2.0); // ranges from ~3 (1 hit) up to 8
    } else if (track.confidence != nil) {
        base = track.confidence.doubleValue;
    }

    // Duration heuristic: prefer 4–8 minutes. Estimate duration from metadata if present, otherwise from spacing to next track.
    double durationSeconds = [self estimatedDurationForTrack:track nextTrack:next];

    double durationScore = 1.0;
    if (durationSeconds <= 0.0) {
        // Unknown duration: give a modest score so single hits are not discarded outright.
        durationScore = 0.30;
    } else if (durationSeconds < 90.0) {
        // Very short (<1.5min): soften the penalty but keep it clearly below ideal.
        double ratio = durationSeconds / _idealTrackMinSeconds; // tiny number
        durationScore = MAX(0.30, 0.30 + 0.70 * ratio);
    } else if (durationSeconds >= _idealTrackMinSeconds && durationSeconds <= _idealTrackMaxSeconds) {
        // Ideal window: strongly reward a solid, full-length track.
        durationScore = 1.60;
    } else if (durationSeconds < _idealTrackMinSeconds) {
        // Short: gentler quadratic falloff; floor at 0.30.
        double ratio = durationSeconds / _idealTrackMinSeconds; // 0..1
        durationScore = MAX(0.30, 0.8 * ratio * ratio);
    } else {
        // Penalize long tracks; make the penalty a bit stronger, floor at 0.15.
        double ratio = _idealTrackMaxSeconds / durationSeconds;
        durationScore = MAX(0.15, 0.8 * ratio);
    }

    double score = base * durationScore;

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

@end

NS_ASSUME_NONNULL_END
