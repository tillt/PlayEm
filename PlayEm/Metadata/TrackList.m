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

- (void)setTrack:(IdentifiedTrack*)track atFrame:(unsigned long long)frame
{
    [_trackMap setObject:track forKey:@(frame)];
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
    *iterator = [[TrackListIterator alloc] initWithKeys:[_trackMap allKeys]];
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
