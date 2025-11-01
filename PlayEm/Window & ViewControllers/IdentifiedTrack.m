//
//  IdentifiedTrack.m
//  PlayEm
//
//  Created by Till Toenshoff on 9/27/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//
#import <Foundation/Foundation.h>
#import <ShazamKit/ShazamKit.h>

#import "IdentifiedTrack.h"

@implementation IdentifiedTrack

- (id)initWithTitle:(NSString*)title artist:(NSString*)artist genre:(NSString*)genre musicURL:(NSURL*)musicURL imageURL:(NSURL*)imageURL
{
    self = [super init];
    if (self) {
        _title = title;
        _artist = artist;
        _genre = genre;
        _imageURL = imageURL;
        _musicURL = musicURL;
    }
    return self;
}

- (id)initWithMatchedMediaItem:(SHMatchedMediaItem*)item
{
    self = [super init];
    if (self) {
        _title = item.title;
        _artist = item.artist;
        _genre = item.genres.count ? item.genres[0] : @"";
        _imageURL = item.artworkURL;
        _musicURL = item.appleMusicURL;
    }
    return self;
}

- (NSString*)description
{
    return [NSString stringWithFormat:@"title:%@ artist:%@ genre:%@ imageURL:%@ musicURL:%@",
            _title, _artist, _genre, _imageURL, _musicURL];
}

@end
