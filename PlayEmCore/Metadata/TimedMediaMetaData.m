//
//  IdentifiedTrack.m
//  PlayEm
//
//  Created by Till Toenshoff on 9/27/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//
#import "TimedMediaMetaData.h"

#import <Foundation/Foundation.h>

#import <AppKit/AppKit.h>
#import <ShazamKit/ShazamKit.h>

#import "MediaMetaData+AVAsset.h"
#import "MediaMetaData.h"

@implementation TimedMediaMetaData

+ (TimedMediaMetaData*)unknownTrackAtFrame:(NSNumber*)frame
{
    TimedMediaMetaData* track = [TimedMediaMetaData new];
    track.meta = [MediaMetaData unknownMediaMetaData];
    track.frame = frame;
    track.confidence = nil;
    return track;
}

- (id)init
{
    self = [super init];
    if (self) {
        _meta = [[MediaMetaData alloc] init];
    }
    return self;
}

- (id)initWithCoder:(NSCoder*)coder
{
    self = [super init];
    if (self) {
        _meta = [coder decodeObjectForKey:@"meta"];
        _frame = [coder decodeObjectForKey:@"frame"];
        _endFrame = [coder decodeObjectForKey:@"endFrame"];
        _confidence = [coder decodeObjectForKey:@"confidence"];
        _supportCount = [coder decodeObjectForKey:@"supportCount"];
        _score = [coder decodeObjectForKey:@"score"];
    }
    return self;
}

- (id)initWithTimedMediaGroup:(AVTimedMetadataGroup*)group framerate:(long)rate
{
    self = [super init];
    if (self) {
        _meta = [MediaMetaData mediaMetaDataWithMetadataItems:group.items];
        double time = (double) group.timeRange.start.value / group.timeRange.start.timescale;
        _frame = [NSNumber numberWithUnsignedLongLong:(unsigned long long) ((double) rate * time)];
        _confidence = nil;
        _score = nil;
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder*)coder
{
    [coder encodeObject:_meta forKey:@"meta"];
    [coder encodeObject:_frame forKey:@"frame"];
    [coder encodeObject:_endFrame forKey:@"endFrame"];
    [coder encodeObject:_confidence forKey:@"confidence"];
    [coder encodeObject:_supportCount forKey:@"supportCount"];
    [coder encodeObject:_score forKey:@"score"];
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (id)initWithMatchedMediaItem:(SHMatchedMediaItem*)item frame:(NSNumber*)frame
{
    self = [super init];
    if (self) {
        _meta = [MediaMetaData mediaMetaDataWithSHMatchedMediaItem:item error:nil];
        _frame = frame;
        _confidence = @(item.confidence);
        _score = nil;
    }
    return self;
}

- (NSString*)description
{
    return [NSString
        stringWithFormat:@"frame:%@ endFrame:%@ support:%@ confidence:%@ score:%@ meta:%@", _frame, _endFrame, _supportCount, _confidence, _score, _meta];
}

@end
