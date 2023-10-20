//
//  MediaMetaData.m
//  PlayEm
//
//  Created by Till Toenshoff on 08.11.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import "MediaMetaData.h"

#import <AVFoundation/AVFoundation.h>

#import <Cocoa/Cocoa.h>

#import <Foundation/Foundation.h>

#import <iTunesLibrary/ITLibMediaItem.h>
#import <iTunesLibrary/ITLibArtist.h>
#import <iTunesLibrary/ITLibAlbum.h>
#import <iTunesLibrary/ITLibArtwork.h>

#import "AVMetadataItem+THAdditions.h"
#import "ITLibMediaItem+TTAdditionsh.h"

@implementation MediaMetaData

+ (MediaMetaData*)mediaMetaDataWithURL:(NSURL*)url error:(NSError**)error
{
    AVAsset* asset = [AVURLAsset URLAssetWithURL:url options:nil];
    NSLog(@"%@", asset);
    return [MediaMetaData mediaMetaDataWithURL:url asset:asset error:error];
}

+ (MediaMetaData*)mediaMetaDataWithURL:(NSURL*)url asset:(AVAsset *)asset error:(NSError**)error
{
    MediaMetaData* meta = [[MediaMetaData alloc] init];

    meta.location = url;

    for (NSString* format in [asset availableMetadataFormats]) {
        for (AVMetadataItem* item in [asset metadataForFormat:format]) {
            NSLog(@"%@ (%@): %@", [item commonKey], [item keyString], [item value]);
            if ([item commonKey] == nil) {
                if ([[item keyString] isEqualToString:@"TYER"] || [[item keyString] isEqualToString:@"@day"]  || [[item keyString] isEqualToString:@"TDRL"] ) {
                    meta.year = [(NSString*)[item value] intValue];
                } else if ([[item keyString] isEqualToString:@"@gen"]) {
                    meta.genre = (NSString*)[item value];
                } else {
                    continue;
                }
            }
            if ([[item commonKey] isEqualToString:@"title"]) {
                meta.title = (NSString*)[item value];
            } else if ([[item commonKey] isEqualToString:@"artist"]) {
                meta.artist = (NSString*)[item value];
            } else if ([[item commonKey] isEqualToString:@"albumName"]) {
                meta.album = (NSString*)[item value];
            } else if ([[item commonKey] isEqualToString:@"type"]) {
                meta.genre = (NSString*)[item value];
            } else if ([[item commonKey] isEqualToString:@"artwork"]) {
                if (item.dataValue != nil) {
                    NSLog(@"item.dataValue artwork");
                    meta.artwork = [[NSImage alloc] initWithData:item.dataValue];
                } else if (item.value != nil) {
                    NSLog(@"item.value artwork");
                    meta.artwork = [[NSImage alloc] initWithData:(id)item.value];
                } else {
                    NSLog(@"unknown artwork");
                }
            } else {
                NSLog(@"questionable metadata: %@ (%@): %@", [item commonKey], [item keyString], [item value]);
            }
        }
    }
    return meta;
}

/*
+ (MediaMetaData*)mediaMetaDataWithAVAsset:(AVAsset*)asset error:(NSError**)error
{
    MediaMetaData* meta = [[MediaMetaData alloc] init];
    return meta;
}
*/

- (NSString*)title
{
    if (_shadow == nil) {
        return _title;
    }
    
    if (_title == nil) {
        _title = _shadow.title;
    }

    return _title;
}

- (NSString*)artist
{
    if (_shadow == nil) {
        return _artist;
    }
    
    if (_artist == nil) {
        _artist = _shadow.artist.name;
    }

    return _artist;
}

- (NSString*)album
{
    if (_shadow == nil) {
        return _album;
    }
    
    if (_album == nil) {
        _album = _shadow.album.title;
    }

    return _album;
}

- (NSString*)genre
{
    if (_shadow == nil) {
        return _genre;
    }
    
    if (_genre == nil) {
        _genre = _shadow.genre;
    }

    return _genre;
}

- (NSUInteger)tempo
{
    if (_shadow == nil) {
        return _tempo;
    }
    
    if (_tempo == 0) {
        _tempo = _shadow.beatsPerMinute;
    }

    return _tempo;
}

- (NSUInteger)year
{
    if (_shadow == nil) {
        return _year;
    }
    
    if (_year == 0) {
        _year = _shadow.year;
    }

    return _year;
}

- (NSUInteger)track
{
    if (_shadow == nil) {
        return _track;
    }
    
    if (_track == 0) {
        _track = _shadow.trackNumber;
    }

    return _track;
}

- (NSURL*)location
{
    if (_shadow == nil) {
        return _location;
    }
    
    if (_location == 0) {
        _location = _shadow.location;
        _locationType = _shadow.locationType;
    }

    return _location;
}

- (NSUInteger)locationType
{
    if (_shadow == nil) {
        return _locationType;
    }
    
    if (_locationType == 0) {
        _locationType = _shadow.locationType;
    }

    return _locationType;
}

- (NSTimeInterval)duration
{
    if (_shadow == nil) {
        return _duration;
    }
    
    if (_duration == 0) {
        _duration = _shadow.totalTime;
    }

    return _duration;
}

- (NSImage*)artwork
{
    if (_shadow == nil) {
        return _artwork;
    }
    
    if (_artwork == nil) {
        if (_shadow.hasArtworkAvailable) {
            _artwork = _shadow.artwork.image;
        } else {
            _artwork = [NSImage imageNamed:@"UnknownSong"];
        }
    }

    return _artwork;
}

- (NSDate*)added
{
    if (_shadow == nil) {
        return _added;
    }
    
    if (_added == nil) {
        _added = _shadow.addedDate;
    }

    return _added;

}

+ (MediaMetaData*)mediaMetaDataWithITLibMediaItem:(ITLibMediaItem*)item error:(NSError**)error
{
    MediaMetaData* meta = [[MediaMetaData alloc] init];
    meta.shadow = item;
    meta.key = @"";
    return meta;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"Title: %@ -- Album: %@ -- Artist: %@ -- Location: %@", self.title, self.album, self.artist, self.location];
}

@end
