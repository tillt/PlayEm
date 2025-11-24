//
//  TrackList.m
//  PlayEm
//
//  Created by Till Toenshoff on 9/27/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import "TrackList.h"
#import "IdentifiedTrack.h"

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
@property (strong, nonatomic) NSMutableDictionary<NSNumber*, IdentifiedTrack*>* trackMap;
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

- (NSString*)beautifulTracksWithFrameEncoder:(FrameToString)encoder
{
    NSString* sheet = @"";

    unsigned long trackIndex = 1;

    NSArray<NSNumber*>* frames = [[self frames] sortedArrayUsingSelector:@selector(compare:)];

    for (NSNumber* value in frames) {
        unsigned long long frame = [value unsignedLongLongValue];
        IdentifiedTrack* track = [self trackAtFrame:frame];

        NSString* entry = [NSString stringWithFormat:@"#%02ld %@ ", trackIndex, encoder(frame)];

        if (track.artist.length > 0 && track.title.length > 0) {
            entry = [NSString stringWithFormat:@"%@%@ - %@", entry, track.artist, track.title];
        } else if (track.title.length > 0) {
            entry = [NSString stringWithFormat:@"%@%@", entry, track.title];
        } else if (track.artist.length > 0) {
            entry = [NSString stringWithFormat:@"%@%@", entry, track.artist];
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
        IdentifiedTrack* track = [self trackAtFrame:frame];
        NSString* entry = [NSString stringWithFormat:@"  TRACK %02ld AUDIO\n", trackIndex];

        if (track.title.length > 0) {
            entry = [NSString stringWithFormat:@"%@    TITLE \"%@\"\n", entry, track.title];
        }
        if (track.artist.length > 0) {
            entry = [NSString stringWithFormat:@"%@    PERFORMER \"%@\"\n", entry, track.artist];
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
    
    NSSet* allowedClasses = [NSSet setWithObjects:[IdentifiedTrack class], [NSString class], [NSNumber class], [NSURL class], nil];
    NSSet* allowedKeyClasses = [NSSet setWithObjects:[NSString class], [NSNumber class], nil];
    NSDictionary* dictionary = [NSKeyedUnarchiver unarchivedDictionaryWithKeysOfClasses:allowedKeyClasses
                                                                       objectsOfClasses:allowedClasses
                                                                               fromData:data error:error];
    if (dictionary == nil) {
        return NO;
    }

    _trackMap = [NSMutableDictionary dictionaryWithDictionary:dictionary];

    return YES;
}

- (void)addTrack:(IdentifiedTrack*)track
{
    [_trackMap setObject:track forKey:track.frame];
}

- (void)removeTrackAtFrame:(unsigned long long)frame
{
    [_trackMap removeObjectForKey:@(frame)];
}

- (NSArray<IdentifiedTrack*>*)tracks
{
    return [_trackMap allValues];
}

- (NSArray<NSNumber*>*)frames
{
    return [_trackMap allKeys];
}

- (IdentifiedTrack*)trackAtFrame:(unsigned long long)frame
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

@end
