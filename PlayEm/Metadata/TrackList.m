//
//  TrackList.m
//  PlayEm
//
//  Created by Till Toenshoff on 9/27/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import "TrackList.h"
#import "TimedMediaMetaData.h"
#import "MediaMetaData.h"
#import <AVFoundation/AVFoundation.h>

@implementation TrackListIterator

- (id)initWithKeys:(NSArray<NSNumber*>*)list
{
    self = [super init];
    if (self) {
        _keys = list;
        _index = 0;
    }
    return self;
}

- (void)next
{
    _index++;
}

- (BOOL)valid
{
    return _index < [_keys count];
}

- (unsigned long long)frame
{
    return [_keys[_index] unsignedLongLongValue];
}

@end

@interface TrackList()
@property (strong, nonatomic) NSMutableDictionary<NSNumber*, TimedMediaMetaData*>* trackMap;
@end

@implementation TrackList

- (id)init
{
    self = [super init];
    if (self) {
        _trackMap = [NSMutableDictionary dictionary];
    }
    return self;
}

- (id)initWithTimedMetadataGroups:(NSArray<AVTimedMetadataGroup*>*)groups framerate:(long)rate
{
    self = [super init];
    if (self) {
        _trackMap = [NSMutableDictionary dictionary];

        for (AVTimedMetadataGroup* group in groups) {
            TimedMediaMetaData* track = [[TimedMediaMetaData alloc] initWithTimedMediaGroup:group framerate:rate];
            NSLog(@"TimedMediaMetaData: %@", track);
            _trackMap[track.frame] = track;
        }
    }
    return self;
}

- (NSString*)beautifulTracksWithFrameEncoder:(FrameToString)encoder
{
    NSString* sheet = @"";

    unsigned long trackIndex = 1;

    NSArray<NSNumber*>* frames = [[self frames] sortedArrayUsingSelector:@selector(compare:)];

    for (NSNumber* value in frames) {
        unsigned long long frame = [value unsignedLongLongValue];
        TimedMediaMetaData* track = [self trackAtFrame:frame];

        NSString* entry = [NSString stringWithFormat:@"#%02ld %@ ", trackIndex, encoder(frame)];

        if (track.meta.artist.length > 0 && track.meta.title.length > 0) {
            entry = [NSString stringWithFormat:@"%@%@ - %@", entry, track.meta.artist, track.meta.title];
        } else if (track.meta.title.length > 0) {
            entry = [NSString stringWithFormat:@"%@%@", entry, track.meta.title];
        } else if (track.meta.artist.length > 0) {
            entry = [NSString stringWithFormat:@"%@%@", entry, track.meta.artist];
        } else {
            entry = [NSString stringWithFormat:@"%@ [Unknown]", entry];
        }
        entry = [NSString stringWithFormat:@"%@\n", entry];

        sheet = [sheet stringByAppendingString:entry];

        trackIndex++;
    }
    return sheet;
}

- (NSString*)cueTracksWithFrameEncoder:(FrameToString)encoder
{
    NSString* sheet = @"";

    unsigned long trackIndex = 1;

    NSArray<NSNumber*>* frames = [[self frames] sortedArrayUsingSelector:@selector(compare:)];

    for (NSNumber* value in frames) {
        unsigned long long frame = [value unsignedLongLongValue];
        TimedMediaMetaData* track = [self trackAtFrame:frame];
        NSString* entry = [NSString stringWithFormat:@"  TRACK %02ld AUDIO\n", trackIndex];

        if (track.meta.title.length > 0) {
            entry = [NSString stringWithFormat:@"%@    TITLE \"%@\"\n", entry, track.meta.title];
        }
        if (track.meta.artist.length > 0) {
            entry = [NSString stringWithFormat:@"%@    PERFORMER \"%@\"\n", entry, track.meta.artist];
        }
        entry = [NSString stringWithFormat:@"%@    INDEX 01 %@\n", entry,  encoder(frame)];

        sheet = [sheet stringByAppendingString:entry];

        trackIndex++;
    }
    return sheet;
}

- (BOOL)writeToFile:(NSURL*)url error:(NSError**)error
{
    NSData* data = [NSKeyedArchiver archivedDataWithRootObject:_trackMap
                                         requiringSecureCoding:NO
                                                         error:error];
    return [data writeToURL:url atomically:YES];
}

- (BOOL)readFromFile:(NSURL*)url error:(NSError**)error
{
    NSData* data = [NSData dataWithContentsOfURL:url
                                         options:NSDataReadingMapped
                                           error:error];
    if (data == nil) {
        return NO;
    }
    
    NSSet* allowedClasses = [NSSet setWithObjects:[TimedMediaMetaData class], [MediaMetaData class], [NSData class], [NSString class], [NSNumber class], [NSURL class], nil];
    NSSet* allowedKeyClasses = [NSSet setWithObjects:[NSString class], [NSNumber class], nil];
    NSDictionary* dictionary = [NSKeyedUnarchiver unarchivedDictionaryWithKeysOfClasses:allowedKeyClasses
                                                                       objectsOfClasses:allowedClasses
                                                                               fromData:data
                                                                                  error:error];
    if (dictionary == nil) {
        return NO;
    }

    _trackMap = [NSMutableDictionary dictionaryWithDictionary:dictionary];

    return YES;
}

- (void)addTrack:(TimedMediaMetaData*)track
{
    [_trackMap setObject:track forKey:track.frame];
}

- (void)removeTrackAtFrame:(unsigned long long)frame
{
    [_trackMap removeObjectForKey:@(frame)];
}

- (NSArray<TimedMediaMetaData*>*)tracks
{
    return [_trackMap allValues];
}

- (NSArray<NSNumber*>*)frames
{
    return [_trackMap allKeys];
}

- (TimedMediaMetaData*)trackAtFrame:(unsigned long long)frame
{
    return [_trackMap objectForKey:@(frame)];
}

- (unsigned long long)firstTrackFrame:(TrackListIterator *_Nonnull*_Nullable)iterator
{
    NSArray<NSNumber*>* frames = [[_trackMap allKeys] sortedArrayUsingSelector:@selector(compare:)];
    *iterator = [[TrackListIterator alloc] initWithKeys:frames];
    return [self nextTrackFrame:*iterator];
}

- (unsigned long long)nextTrackFrame:(nonnull TrackListIterator *)iterator
{
    if (![iterator valid]) {
        return ULONG_LONG_MAX;
    }
    unsigned long long frame = iterator.frame;
    [iterator next];
    return frame;
}

- (NSString*)description
{
    return [NSString stringWithFormat:@"%@", _trackMap];
}

@end
