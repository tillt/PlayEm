//
//  IdentifiedTrack.m
//  PlayEm
//
//  Created by Till Toenshoff on 9/27/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//
#import "IdentifiedTrack.h"

#import <Foundation/Foundation.h>

#import <AppKit/AppKit.h>
#import <ShazamKit/ShazamKit.h>

#import "MediaMetaData.h"

@implementation IdentifiedTrack

+ (IdentifiedTrack*)unknownTrackAtFrame:(NSNumber*)frame
{
    IdentifiedTrack* track = [[IdentifiedTrack alloc] initWithTitle:@"unknown" artist:@"unknown" genre:@"" musicURL:nil imageURL:nil frame:frame];
    track.artwork = [NSImage imageNamed:@"UnknownSong"];
    return track;
}

- (id)initWithTitle:(NSString*)title artist:(NSString*)artist genre:(NSString*)genre musicURL:(NSURL*)musicURL imageURL:(NSURL*)imageURL frame:(NSNumber*)frame
{
    self = [super init];
    if (self) {
        _title = title;
        _artist = artist;
        _genre = genre;
        _imageURL = imageURL;
        _musicURL = musicURL;
        _frame = frame;
    }
    return self;
}

- (id)initWithCoder:(NSCoder*)coder
{
    self = [super init];
    if (self) {
        _title = [coder decodeObjectForKey:@"title"];
        _artist = [coder decodeObjectForKey:@"artist"];
        _genre = [coder decodeObjectForKey:@"genre"];
        _imageURL = [coder decodeObjectForKey:@"imageURL"];
        _musicURL = [coder decodeObjectForKey:@"musicURL"];
        _frame = [coder decodeObjectForKey:@"frame"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder*)coder
{
    [coder encodeObject:_title forKey:@"title"];
    [coder encodeObject:_artist forKey:@"artist"];
    [coder encodeObject:_genre forKey:@"genre"];
    [coder encodeObject:_imageURL forKey:@"imageURL"];
    [coder encodeObject:_musicURL forKey:@"musicURL"];
    [coder encodeObject:_frame forKey:@"frame"];
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (id)initWithMatchedMediaItem:(SHMatchedMediaItem*)item
{
    self = [super init];
    if (self) {
        _meta = [];
        _title = item.title;
        _artist = item.artist;
        _genre = item.genres.count ? item.genres[0] : @"";
        _imageURL = item.artworkURL;
        _musicURL = item.appleMusicURL;
        _frame = 0LL;
    }
    return self;
}

- (NSString*)description
{
    return [NSString stringWithFormat:@"frame:%@ title:%@ artist:%@ genre:%@ imageURL:%@ musicURL:%@", _frame, _title, _artist, _genre, _imageURL, _musicURL];
}

@end
