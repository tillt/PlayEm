//
//  MediaMetaData.m
//  PlayEm
//
//  Created by Till Toenshoff on 08.11.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//
#include <stdlib.h>
#import "MediaMetaData.h"

#import <AVFoundation/AVFoundation.h>
#import <iTunesLibrary/ITLibArtist.h>
#import <iTunesLibrary/ITLibAlbum.h>

#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>

#import <Foundation/Foundation.h>

#import "MediaMetaData+TagLib.h"
#import "MediaMetaData+AVAsset.h"

#import "NSURL+WithoutParameters.h"
#import "NSString+BeautifulPast.h"
#import "NSString+OccurenceCount.h"

///
/// MediaMetaData is lazily holding metadata for library entries to allow for extending iTunes provided data.
/// iTunes provided data are held in a shadow item until data is requested and thus copied in. iTunes metadata
/// is asynchronously requested through ITLibMediaItem on demand.
///

//NSString* const kStarSymbol = @"􀋃";
NSString* const kMediaMetaDataMapKeyMP3 = @"mp3";
NSString* const kMediaMetaDataMapKeyMP4 = @"mp4";
NSString* const kMediaMetaDataMapKeyType = @"type";
NSString* const kMediaMetaDataMapKey = @"key";
NSString* const kMediaMetaDataMapIdentifier = @"identifier";
NSString* const kMediaMetaDataMapKeys = @"keys";
NSString* const kMediaMetaDataMapOrder = @"order";
NSString* const kMediaMetaDataMapTypeString = @"string";
NSString* const kMediaMetaDataMapTypeDate = @"date";
NSString* const kMediaMetaDataMapTypeImage = @"image";
NSString* const kMediaMetaDataMapTypeTuple = @"tuple";
NSString* const kMediaMetaDataMapTypeTuple48 = @"tuple48";
NSString* const kMediaMetaDataMapTypeTuple64 = @"tuple64";
NSString* const kMediaMetaDataMapTypeNumber = @"number";

@interface MediaMetaData ()
@property (readonly, nonatomic, nullable) NSDictionary* starsQuantums;
@end

@implementation MediaMetaData

+ (NSDictionary*)starsQuantums
{
    static NSDictionary* quantums = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        quantums = @{
            @(0): @"",
            @(1): @"􀋃",
            @(2): @"􀋃􀋃",
            @(3): @"􀋃􀋃􀋃",
            @(4): @"􀋃􀋃􀋃􀋃",
            @(5): @"􀋃􀋃􀋃􀋃􀋃"
          };
    });
    return quantums;
}

+ (MediaMetaDataFileFormatType)fileTypeWithURL:(NSURL*)url error:(NSError**)error
{
    if (url == nil) {
        NSString* description = @"Cannot identify item as it lacks a location";
        if (error) {
            NSDictionary* userInfo = @{
                NSLocalizedDescriptionKey: description,
            };
            *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier]
                                         code:-1
                                     userInfo:userInfo];
        }
        NSLog(@"error: %@", description);
        return MediaMetaDataFileFormatTypeUnknown;
    }
    
    NSString* fileExtension = [url pathExtension];
    
    if ([fileExtension isEqualToString:@"mp4"] 
        || [fileExtension isEqualToString:@"m4v"]
        || [fileExtension isEqualToString:@"m4r"]
        || [fileExtension isEqualToString:@"m4a"]) {
        return MediaMetaDataFileFormatTypeMP4;
    }
    if ([fileExtension isEqualToString:@"mp3"]) {
        return MediaMetaDataFileFormatTypeMP3;
    }
    if ([fileExtension isEqualToString:@"aif"] 
        || [fileExtension isEqualToString:@"aiff"]) {
        return MediaMetaDataFileFormatTypeAIFF;
    }
    if ([fileExtension isEqualToString:@"wav"]) {
        return MediaMetaDataFileFormatTypeWAV;
    }

    NSString* description = [NSString stringWithFormat:@"Unknown file type (%@)", fileExtension];
    if (error) {
        NSDictionary* userInfo = @{
            NSLocalizedDescriptionKey: description,
        };
        *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier]
                                     code:-1
                                 userInfo:userInfo];
    }
    NSLog(@"error: %@", description);
    return MediaMetaDataFileFormatTypeUnknown;
}

+ (MediaMetaData*)mediaMetaDataWithURL:(NSURL*)url error:(NSError**)error
{
    MediaMetaData* meta = [[MediaMetaData alloc] init];
    meta.location = [[url filePathURL] URLWithoutParameters];
    [meta readFromFileWithError:error];
    return meta;
}

+ (MediaMetaData*)mediaMetaDataWithURL:(NSURL*)url asset:(AVAsset*)asset error:(NSError**)error
{
    MediaMetaData* meta = [[MediaMetaData alloc] init];
    meta.location = [url URLWithoutParameters];
    [meta readFromAVAsset:asset];
    return meta;
}

+ (MediaMetaData*)mediaMetaDataWithITLibMediaItem:(ITLibMediaItem*)item error:(NSError**)error
{
    MediaMetaData* meta = [[MediaMetaData alloc] init];
    meta.shadow = item;
    meta.key = @"";
    return meta;
}

+ (NSDictionary<NSString*, NSDictionary*>*)mediaMetaKeyMap
{
    return @{
        @"added": @{},
        @"location": @{},
        @"size": @{},
        @"format": @{},
        @"bitrate": @{},
        @"samplerate": @{},
        @"channels": @{},
        @"locationType": @{},

        @"volumeAdjustment": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKey: @"RelativeVolumeFrame",
            },
        },

        @"album": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKey: @"ALBUM",
            },
            kMediaMetaDataMapKeyMP4: @{
                kMediaMetaDataMapKey: AVMetadataiTunesMetadataKeyAlbum,
            },
        },
        @"albumArtist": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKey: @"ALBUMARTIST",
            },
            kMediaMetaDataMapKeyMP4: @{
                kMediaMetaDataMapKey: AVMetadataiTunesMetadataKeyAlbumArtist,
            },
        },
        @"artist": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKey: @"ARTIST",
            },
            kMediaMetaDataMapKeyMP4: @{
                kMediaMetaDataMapKey: AVMetadataiTunesMetadataKeyArtist,
            },
        },
        @"artwork": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKey: @"PICTURE",
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeImage,
            },
            kMediaMetaDataMapKeyMP4: @{
                kMediaMetaDataMapKey: AVMetadataiTunesMetadataKeyCoverArt,
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeImage,
            },
        },
        @"comment": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKey: @"COMMENT",
            },
            kMediaMetaDataMapKeyMP4: @{
                kMediaMetaDataMapKey: AVMetadataiTunesMetadataKeyUserComment,
            },
        },
        @"composer": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKey: @"COMPOSER",
            },
            kMediaMetaDataMapKeyMP4: @{
                kMediaMetaDataMapKey: AVMetadataiTunesMetadataKeyComposer,
            },
        },
        @"compilation": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKey: @"COMPILATION",
            },
            kMediaMetaDataMapKeyMP4: @{
                kMediaMetaDataMapKey: AVMetadataiTunesMetadataKeyDiscCompilation,
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeNumber,
            },
        },
        @"lyrics": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKey: @"LYRICS",
            },
            kMediaMetaDataMapKeyMP4: @{
                kMediaMetaDataMapKey: AVMetadataiTunesMetadataKeyLyrics,
            },
        },
        @"label": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKey: @"LABEL",
            },
            kMediaMetaDataMapKeyMP4: @{
                kMediaMetaDataMapKey: AVMetadataiTunesMetadataKeyRecordCompany,
            },
        },
        @"disk": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKey: @"DISCNUMBER",
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeTuple,
                kMediaMetaDataMapOrder: @0,
            },
            kMediaMetaDataMapKeyMP4: @{
                kMediaMetaDataMapKey: AVMetadataiTunesMetadataKeyDiscNumber,
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeTuple,
                kMediaMetaDataMapOrder: @0,
            },
        },
        @"disks": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKey: @"DISCNUMBER",
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeTuple,
                kMediaMetaDataMapOrder: @1,
            },
            kMediaMetaDataMapKeyMP4: @{
                kMediaMetaDataMapKey: AVMetadataiTunesMetadataKeyDiscNumber,
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeTuple,
                kMediaMetaDataMapOrder: @1,
            },
        },
// Duration from MP3 ID3 tags is commonly not exact enough for our purposes.
//        @"duration": @{
//            kMediaMetaDataMapKeyMP3: @{
//                kMediaMetaDataMapKey: @"LENGTH",
//                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeNumber,
//            },
//        },
        @"genre": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKey: @"GENRE",
            },
            kMediaMetaDataMapKeyMP4: @{
                kMediaMetaDataMapKey: AVMetadataiTunesMetadataKeyUserGenre,
            },
        },
        @"key": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKey: @"INITIALKEY",
            },
        },
        @"rating": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKey: @"RATING",
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeNumber,
            },
            kMediaMetaDataMapKeyMP4: @{
                kMediaMetaDataMapKey: AVMetadataiTunesMetadataKeyContentRating,
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeNumber,
            },
        },
        @"tags": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKey: @"GROUPING",
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeString,
            },
            kMediaMetaDataMapKeyMP4: @{
                kMediaMetaDataMapKey: AVMetadataiTunesMetadataKeyGrouping,
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeString,
            },
        },
        @"tempo": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKey: @"BPM",
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeNumber,
            },
            kMediaMetaDataMapKeyMP4: @{
                kMediaMetaDataMapKey: AVMetadataiTunesMetadataKeyBeatsPerMin,
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeNumber,
            },
        },
        @"title": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKey: @"TITLE",
            },
            kMediaMetaDataMapKeyMP4: @{
                kMediaMetaDataMapKey: AVMetadataiTunesMetadataKeySongName,
            },
        },
        @"track": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKey: @"TRACKNUMBER",
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeTuple,
                kMediaMetaDataMapOrder: @0,
            },
            kMediaMetaDataMapKeyMP4: @{
                kMediaMetaDataMapKey: AVMetadataiTunesMetadataKeyTrackNumber,
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeTuple,
                kMediaMetaDataMapOrder: @0,
            },
        },
        @"volume": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKey: @"VOLUME",
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeNumber,
            },
            kMediaMetaDataMapKeyMP4: @{
                kMediaMetaDataMapKey: AVMetadataID3MetadataKeyRelativeVolumeAdjustment,
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeNumber,
            },
        },

        @"tracks": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKey: @"TRACKNUMBER",
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeTuple,
                kMediaMetaDataMapOrder: @1,
            },
            kMediaMetaDataMapKeyMP4: @{
                kMediaMetaDataMapKey: AVMetadataiTunesMetadataKeyTrackNumber,
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeTuple,
                kMediaMetaDataMapOrder: @1,
            },
        },
        @"year": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKey: @"DATE",
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeDate,
            },
            kMediaMetaDataMapKeyMP4: @{
                kMediaMetaDataMapKey: AVMetadataiTunesMetadataKeyReleaseDate,
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeDate,
            },
        },
    };
}

+ (NSArray<NSString*>*)mediaMetaKeys
{
    return [[MediaMetaData mediaMetaKeyMap] allKeys];
}

+ (NSArray<NSString*>*)mediaDataKeysWithFileFormatType:(MediaMetaDataFileFormatType)type
{
    NSDictionary<NSString*, NSDictionary*>* mediaMetaKeyMap = [MediaMetaData mediaMetaKeyMap];
    NSMutableArray<NSString*>* supportedKeys = [NSMutableArray array];

    NSString* typeKey = nil;

    switch(type) {
        case MediaMetaDataFileFormatTypeMP3:
            typeKey = kMediaMetaDataMapKeyMP3;
            break;
        case MediaMetaDataFileFormatTypeMP4:
            typeKey = kMediaMetaDataMapKeyMP4;
            break;
        default:
            ;
    }
    
    if (typeKey == nil) {
        return [NSArray array];
    }
    
    for (NSString* key in [MediaMetaData mediaMetaKeys]) {
        if ([mediaMetaKeyMap[key] objectForKey:typeKey]) {
            [supportedKeys addObject:key];
        }
    }

    return supportedKeys;
}

+ (ITLibArtworkFormat)artworkFormatForData:(NSData*)data
{
    uint8_t c;

    [data getBytes:&c length:1];

    switch(c) {
        case 0xFF:
            return ITLibArtworkFormatJPEG;
        case 0x89:
            return ITLibArtworkFormatPNG;
        case 0x47:
            return ITLibArtworkFormatGIF;
        case 0x49:
        case 0x4D:
            return ITLibArtworkFormatTIFF;
    }
    return ITLibArtworkFormatNone;
}

+ (NSString*)mimeTypeForArtworkFormat:(ITLibArtworkFormat)format
{
    /*
     ITLibArtworkFormatNone = 0,
     ITLibArtworkFormatBitmap = 1,
     ITLibArtworkFormatJPEG = 2,
     ITLibArtworkFormatJPEG2000 = 3,
     ITLibArtworkFormatGIF = 4,
     ITLibArtworkFormatPNG = 5,
     ITLibArtworkFormatBMP = 6,
     ITLibArtworkFormatTIFF = 7,
     ITLibArtworkFormatPICT = 8
     */
    NSDictionary* mimeMap = @{
        @(ITLibArtworkFormatJPEG): @"image/jpeg",
        @(ITLibArtworkFormatGIF): @"image/gif",
        @(ITLibArtworkFormatPNG): @"image/png",
        @(ITLibArtworkFormatBMP): @"image/bmp",
        @(ITLibArtworkFormatTIFF): @"image/tiff",
    };
    
    return mimeMap[@(format)];
}

- (NSString*)mimeTypeForArtwork
{
    if (self.artwork == nil) {
        return nil;
    }
    return [MediaMetaData mimeTypeForArtworkFormat:[self.artworkFormat integerValue]];
}

- (NSString* _Nullable)title
{
    if (_shadow == nil) {
        return _title;
    }
    
    if (_title == nil) {
        _title = _shadow.title;
    }
    
    return _title;
}

- (NSString* _Nullable)size
{
    if (_shadow == nil) {
        return _size;
    }
    
    if (_size == nil) {
        _size = [NSString BeautifulSize:[NSNumber numberWithUnsignedLongLong:_shadow.fileSize]];
    }
    
    return _size;
}

- (NSString* _Nullable)format
{
    if (_shadow == nil) {
        return _format;
    }
    
    if (_format == nil) {
        _format = _shadow.kind;
    }
    
    return _format;
}

- (NSString* _Nullable)samplerate
{
    if (_shadow == nil) {
        return _samplerate;
    }
    
    if (_samplerate == nil) {
        _samplerate = [NSString stringWithFormat:@"%.1f kHz", _shadow.sampleRate / 1000.0f];
    }
    
    return _samplerate;
}

- (NSString* _Nullable)channels
{
    if (_shadow == nil) {
        return _channels;
    }
    
    if (_channels == nil) {
        _channels = @"stereo";
    }
    
    return _channels;
}

- (NSString* _Nullable)bitrate
{
    if (_shadow == nil) {
        return _bitrate;
    }
    
    if (_bitrate == nil) {
        _bitrate = [NSString stringWithFormat:@"%ld kbps", (unsigned long)_shadow.bitrate];
    }
    
    return _bitrate;
}

- (NSString* _Nullable)volume
{
    if (_shadow == nil) {
        return _volume;
    }
    
    if (_volume == nil) {
        _volume = [NSString stringWithFormat:@"%.1f dB", 16.0];   // FIXME: what gives?
    }
    
    return _volume;
}

- (NSString* _Nullable)volumeAdjustment
{
    if (_shadow == nil) {
        return _volumeAdjustment;
    }
    
    if (_volumeAdjustment == nil) {
        _volumeAdjustment = [NSString stringWithFormat:@"%ld dB", (long)_shadow.volumeAdjustment];
    }
    
    return _volumeAdjustment;
}

- (NSString* _Nullable)artist
{
    if (_shadow == nil) {
        return _artist;
    }
    
    if (_artist == nil) {
        _artist = _shadow.artist.name;
    }
    
    return _artist;
}

- (NSString* _Nullable)album
{
    if (_shadow == nil) {
        return _album;
    }
    
    if (_album == nil) {
        _album = _shadow.album.title;
    }
    
    return _album;
}

- (NSString* _Nullable)albumArtist
{
    if (_shadow == nil) {
        return _albumArtist;
    }
    
    if (_albumArtist == nil) {
        _albumArtist = _shadow.album.albumArtist;
    }
    
    return _albumArtist;
}

- (NSString* _Nullable)genre
{
    if (_shadow == nil) {
        return _genre;
    }
    
    if (_genre == nil) {
        _genre = _shadow.genre;
    }
    
    return _genre;
}

- (NSString* _Nullable)composer
{
    if (_shadow == nil) {
        return _composer;
    }
    
    if (_composer == nil) {
        _composer = _shadow.composer;
    }
    
    return _composer;
}

- (NSString* _Nullable)comment
{
    if (_shadow == nil) {
        return _comment;
    }
    
    if (_comment == nil) {
        _comment = _shadow.comments;
    }
    
    return _comment;
}

- (NSNumber* _Nullable)tempo
{
    if (_shadow == nil) {
        return _tempo;
    }
    
    if (_tempo == nil) {
        _tempo = [NSNumber numberWithUnsignedInteger:_shadow.beatsPerMinute];
    }
    
    return _tempo;
}

- (void)setStars:(NSString*)stars
{
    NSDictionary* starsQuantums = [MediaMetaData starsQuantums];
    NSString* star = starsQuantums[@(1)];
    NSUInteger rating = [stars occurrenceCountOfString:star];
    self.rating = [NSNumber numberWithUnsignedLong:rating * 20];
}

+ (NSArray<NSString*>*)starRatings
{
    return [[MediaMetaData starsQuantums] allValues];
}

+ (NSString*)starsWithRating:(NSNumber*)rating
{
    NSString* string = @"";
    int r = [rating intValue];
    if (r > 0) {
        NSDictionary* quantums = [MediaMetaData starsQuantums];
        int index = (r + 19) / 20;
        assert(index < 6);
        NSNumber* number = [NSNumber numberWithInt:index];
        assert([quantums objectForKey:number] != nil);
        string = quantums[[NSNumber numberWithInt:index]];
    }
    return string;
}

- (NSString*)stars
{
    return [MediaMetaData starsWithRating:self.rating];
}

- (NSNumber* _Nullable)rating
{
    if (_shadow == nil) {
        return _rating;
    }
    
    if (_rating == nil) {
        _rating = [NSNumber numberWithUnsignedInteger:_shadow.rating];
    }
    
    return _rating;
}

- (NSString* _Nullable)tags
{
    if (_shadow == nil) {
        return _tags;
    }
    
    if (_tags == nil) {
        _tags = _shadow.grouping;
    }
    
    return _tags;
}

- (NSNumber* _Nullable)year
{
    if (_shadow == nil) {
        return _year;
    }
    
    if (_year == nil) {
        _year = [NSNumber numberWithUnsignedInteger:_shadow.year];
    }
    
    return _year;
}

- (NSNumber* _Nullable)track
{
    if (_shadow == nil) {
        return _track;
    }
    
    if (_track == nil) {
        _track = [NSNumber numberWithUnsignedInteger:_shadow.trackNumber];
    }
    
    return _track;
}

- (NSNumber* _Nullable)tracks
{
    if (_shadow == nil) {
        return _tracks;
    }
    
    if (_tracks == nil) {
        _tracks = [NSNumber numberWithUnsignedInteger:_shadow.album.trackCount];
    }
    
    return _tracks;
}

- (NSNumber* _Nullable)disk
{
    if (_shadow == nil) {
        return _disk;
    }
    
    if (_disk == nil) {
        _disk = [NSNumber numberWithUnsignedInteger:_shadow.album.discNumber];
    }
    
    return _disk;
}

- (NSNumber* _Nullable)disks
{
    if (_shadow == nil) {
        return _disks;
    }
    
    if (_disks == nil) {
        _disks = [NSNumber numberWithUnsignedInteger:_shadow.album.discCount];
    }
    
    return _disks;
}

- (NSURL* _Nullable)location
{
    if (_shadow == nil) {
        return _location;
    }
    
    if (_location == nil) {
        _location = _shadow.location;
    }
    
    return _location;
}

- (NSNumber* _Nullable)locationType
{
    if (_shadow == nil) {
        return _locationType;
    }
    
    if (_locationType == nil) {
        _locationType = [NSNumber numberWithUnsignedInteger:_shadow.locationType];
    }
    
    return _locationType;
}

- (NSNumber* _Nullable)duration
{
    if (_shadow == nil) {
        return _duration;
    }
    
    if (_duration == nil) {
        _duration = [NSNumber numberWithFloat:_shadow.totalTime];
    }
    
    return _duration;
}

- (NSNumber* _Nullable)compilation
{
    if (_shadow == nil) {
        return _compilation;
    }
    
    if (_compilation == nil) {
        _compilation = [NSNumber numberWithBool:_shadow.album.compilation];
    }
    
    return _compilation;
}

- (NSData* _Nullable)artwork
{
    if (_shadow == nil) {
        return _artwork;
    }

    if (_artwork == nil) {
        if (_shadow.hasArtworkAvailable && _shadow.artwork) {
            _artwork = _shadow.artwork.imageData;
        }
    }
    
    return _artwork;
}

- (NSNumber* _Nullable)artworkFormat
{
    if (_shadow == nil) {
        return _artworkFormat;
    }
    
    if (_artworkFormat == nil) {
        _artworkFormat = [NSNumber numberWithInteger:_shadow.artwork.imageDataFormat];
    }
    
    return _artworkFormat;
}

- (NSImage*)imageFromArtwork
{
    if (self.artwork == nil) {
        return [NSImage imageNamed:@"UnknownSong"];
    }

    return [[NSImage alloc] initWithData:self.artwork];
}

- (NSDate* _Nullable)added
{
    if (_shadow == nil) {
        return _added;
    }
    
    if (_added == nil) {
        _added = _shadow.addedDate;
    }
    
    return _added;
}

- (NSString*)description
{
    return [NSString stringWithFormat:@"Title: %@ -- Album: %@ -- Artist: %@ -- Location: %@ -- Address: %p -- Artwork format: %@ -- Tempo: %@ -- Key: %@ -- Duration: %@ -- Rating: %@ -- Comment: %@",
            self.title, self.album, self.artist, self.location, (void*)self, self.artworkFormat, self.tempo, self.key, self.duration, self.rating, self.comment];
}

- (id)copyWithZone:(NSZone *)zone
{
    MediaMetaData* copy = [[[self class] allocWithZone:zone] init];
    if (copy != nil) {
        copy.title = [_title copyWithZone:zone];
        copy.album = [_album copyWithZone:zone];
        copy.artist = [_artist copyWithZone:zone];
        copy.genre = [_genre copyWithZone:zone];
        copy.year = [_year copyWithZone:zone];
        copy.comment = [_comment copyWithZone:zone];
        copy.lyrics = [_lyrics copyWithZone:zone];
        copy.composer = [_composer copyWithZone:zone];
        copy.compilation = [_compilation copyWithZone:zone];
        copy.albumArtist = [_albumArtist copyWithZone:zone];
        copy.label = [_label copyWithZone:zone];
        copy.tempo = [_tempo copyWithZone:zone];
        copy.albumArtist = [_albumArtist copyWithZone:zone];
        copy.key = [_key copyWithZone:zone];
        copy.track = [_track copyWithZone:zone];
        copy.tracks = [_tracks copyWithZone:zone];
        copy.disk = [_disk copyWithZone:zone];
        copy.disks = [_disks copyWithZone:zone];
        copy.locationType = [_locationType copyWithZone:zone];
        copy.artwork = [_artwork copyWithZone:zone];
        copy.artworkFormat = [_artworkFormat copyWithZone:zone];
        copy.location = [_location copyWithZone:zone];
        copy.added = [_added copyWithZone:zone];
        copy.duration = [_duration copyWithZone:zone];
        copy.size = [_size copyWithZone:zone];
        copy.rating = [_rating copyWithZone:zone];
        copy.tags = [_tags copyWithZone:zone];
        copy.channels = [_channels copyWithZone:zone];
        copy.bitrate = [_bitrate copyWithZone:zone];
        copy.volume = [_volume copyWithZone:zone];
        copy.volumeAdjustment = [_volumeAdjustment copyWithZone:zone];
        copy.samplerate = [_samplerate copyWithZone:zone];

        copy.shadow = _shadow;
    }
    return copy;
}

- (NSString* _Nullable)stringForKey:(NSString*)key
{
    id valueObject = [self valueForKey:key];
    
    if ([valueObject isKindOfClass:[NSString class]]) {
        return valueObject;
    }
    
    if ([valueObject isKindOfClass:[NSNumber class]] && 
        [valueObject intValue] > 0) {
        return [valueObject stringValue];
    }
    
    if ([valueObject isKindOfClass:[NSURL class]]) {
        return [[valueObject absoluteString] stringByRemovingPercentEncoding];
    }
    
    if ([valueObject isKindOfClass:[NSDate class]]) {
        return [NSDateFormatter localizedStringFromDate:valueObject
                                              dateStyle:NSDateFormatterShortStyle
                                              timeStyle:NSDateFormatterNoStyle];
    }
    
    return @"";
}

- (BOOL)isEqualToMediaMetaData:(MediaMetaData*)other atKey:key
{
    if (other == nil) {
        return NO;
    }
    
    // Special treatment for `artwork`.
    if ([key isEqualToString:@"artwork"]) {
        NSData* thisData = self.artwork;
        NSData* otherData = other.artwork;
        
        if (![thisData isEqualToData:otherData]) {
            NSLog(@"mismatch at artwork");
            return NO;
        }
    } else {
        NSString* thisValue = [self stringForKey:key];
        NSString* otherValue = [other stringForKey:key];
        
        if (![thisValue isEqualToString:otherValue]) {
            NSLog(@"mismatch at key %@ with \"%@\" != \"%@\"", key, thisValue, otherValue);
            return NO;
        }
    }
    
    return YES;
}

- (BOOL)isEqualToMediaMetaData:(MediaMetaData*)other forKeys:(NSArray<NSString*>*)keys
{
    if (other == nil) {
        return NO;
    }
    
    for (NSString* key in keys) {
        if (![self isEqualToMediaMetaData:other atKey:key]) {
            return NO;
        }
    }
    
    return YES;
}

- (BOOL)isEqualToMediaMetaData:(MediaMetaData*)other
{
    if (other == nil) {
        return NO;
    }
    MediaMetaDataFileFormatType thisType = [MediaMetaData fileTypeWithURL:self.location
                                                                    error:nil];
    MediaMetaDataFileFormatType otherType = [MediaMetaData fileTypeWithURL:other.location
                                                                     error:nil];
    if (thisType != otherType) {
        NSLog(@"file types differ");
        return NO;
    }
    
    NSArray<NSString*>* supportedKeys = [MediaMetaData mediaDataKeysWithFileFormatType:thisType];
    return [self isEqualToMediaMetaData:other forKeys:supportedKeys];
}

- (void)updateWithKey:(NSString*)key string:(NSString*)string
{
    // Rather involved way to retrieve the Class from a member (that may be set to nil).
    objc_property_t property = class_getProperty(self.class, 
                                                 [key cStringUsingEncoding:NSUTF8StringEncoding]);
    const char* const attrString = property_getAttributes(property);
    const char* typeString = attrString + 1;
    const char* className = typeString + 2;
    const char* next = strchr(className, '"');
    size_t classNameLength = next - className;
    char trimmedName[classNameLength + 1];
    strncpy(trimmedName, className, classNameLength);
    trimmedName[classNameLength] = '\0';
    Class objectClass = objc_getClass(trimmedName);
    
    if (objectClass == [NSString class]) {
        [self setValue:string forKey:key];
        return;
    }
    
    if (objectClass == [NSNumber class]) {
        NSInteger integerValue = [string integerValue];
        NSNumber* numberValue = [NSNumber numberWithInteger:integerValue];
        [self setValue:numberValue forKey:key];
        return;
    }

    if (objectClass == [NSURL class]) {
        NSURL* urlValue = [NSURL URLWithString:string];
        [self setValue:urlValue forKey:key];
        return;
    }

    NSAssert(NO, @"should never get here");
}

+ (NSString* _Nullable)correctedKeyNotation:(NSString* _Nullable)key
{
    // We are trying to catch all synonymous scales here additionally
    // to the 24 sectors of the MixWheel.
    NSDictionary* mixWheel = @{
        @"Abmin": @"1A",    // G♯ minor/A♭ minor
        @"G#min": @"1A",    // G♯ minor/A♭ minor
        @"Cbmaj": @"1B",    // B major/C♭ major
        @"Bmaj":  @"1B",    // B major/C♭ major
        @"Ebmin": @"2A",    // D♯ minor/E♭ minor
        @"D#min": @"2A",    // D♯ minor/E♭ minor
        @"F#maj": @"2B",    // F♯ major/G♭ major
        @"Gbmaj": @"2B",    // F♯ major/G♭ major
        @"A#min": @"3A",    // A♯ minor/B♭ minor
        @"Bbmin": @"3A",    // A♯ minor/B♭ minor
        @"C#maj": @"3B",    // C♯ major/D♭ major
        @"Dbmaj": @"3B",    // C♯ major/D♭ major
        @"Fmin":  @"4A",
        @"Abmaj": @"4B",    // G♯ major/A♭ major
        @"G#maj": @"4B",    // G♯ major/A♭ major
        @"Cmin":  @"5A",
        @"Ebmaj": @"5B",    // D♯ major/E♭ major
        @"D#maj": @"5B",    // D♯ major/E♭ major
        @"Gmin":  @"6A",
        @"A#maj": @"6B",    // A♯ major/B♭ major
        @"Bbmaj": @"6B",    // A♯ major/B♭ major
        @"Dmin":  @"7A",
        @"Fmaj":  @"7B",
        @"Amin":  @"8A",
        @"Cmaj":  @"8B",
        @"Emin":  @"9A",
        @"Gmaj":  @"9B",
        @"Cbmin": @"10A",   // B minor/C♭ minor
        @"Bmin":  @"10A",   // B minor/C♭ minor
        @"Dmaj":  @"10B",
        @"Gbmin": @"11A",   // F♯ minor/G♭ minor
        @"F#min": @"11A",   // F♯ minor/G♭ minor
        @"Amaj":  @"11B",
        @"C#min": @"12A",   // C♯ minor/D♭ minor
        @"Dbmin": @"12A",
        @"Emaj":  @"12B",
    };
    
    if (key == nil || key.length == 0) {
        return key;
    }

    // Shortcut when the given key a proper one already.
    NSArray* properValues = [mixWheel allValues];
    if ([properValues indexOfObject:key] != NSNotFound) {
        return key;
    }

    // Easy cases map already, shortcut those.
    NSString* mappedKey = [mixWheel objectForKey:key];
    if (mappedKey != nil) {
        return mappedKey;
    }

    if (key.length > 1) {
        // Lets patch minor defects in place so we can map later...
        // Get a possible note specifier.
        NSString* s = [key substringWithRange:NSMakeRange(1,1)];
        if ([s isEqualToString:@"o"] || [s isEqualToString:@"♯"]) {
            key = [NSString stringWithFormat:@"%@#%@", [key substringToIndex:1], [key substringFromIndex:2]];
        } else if ([s isEqualToString:@"♭"]) {
            key = [NSString stringWithFormat:@"%@b%@", [key substringToIndex:1], [key substringFromIndex:2]];
        }
    }

    NSString* patchedKey = nil;
    unichar p = [key characterAtIndex:0];
    unichar t = [key characterAtIndex:key.length - 1];

    if ((p >= '1' && p <= '9')) {
        if (t == 'm' || t == 'n') {
            patchedKey = [NSString stringWithFormat:@"%@A", [key substringToIndex:key.length - 1]];
        } else {
            patchedKey = [NSString stringWithFormat:@"%@B", key];
        }
        return patchedKey;
    } 

    if (t == 'm') {
        patchedKey = [NSString stringWithFormat:@"%@in", key];
    } else if (t != 'n') {
        patchedKey = [NSString stringWithFormat:@"%@maj", key];
    } else {
        patchedKey = key;
    }
    
    mappedKey = [mixWheel objectForKey:patchedKey];
    if (mappedKey != nil) {
        return mappedKey;
    }
    
    NSLog(@"couldnt map key %@ (%@)", key, patchedKey);
    return key;
}

- (BOOL)readFromFileWithError:(NSError**)error
{
    MediaMetaDataFileFormatType type = [MediaMetaData fileTypeWithURL:self.location error:error];
    
    BOOL ret = NO;
    if (type == MediaMetaDataFileFormatTypeMP3) {
        ret = [self readFromMP3FileWithError:error] == 0;
    }
    if (type == MediaMetaDataFileFormatTypeMP4) {
        ret = [self readFromMP4FileWithError:error];
    }
    if (type == MediaMetaDataFileFormatTypeWAV || type == MediaMetaDataFileFormatTypeAIFF) {
        ret = [self readFromMP3FileWithError:error];
    }
    if (ret == YES) {
        _key = [MediaMetaData correctedKeyNotation:_key];
    }
    return ret;
}

- (BOOL)writeToFileWithError:(NSError**)error
{
    if (self.location == nil) {
        NSString* description = @"Cannot sync item back as it lacks a location";
        if (error) {
            NSDictionary* userInfo = @{
                NSLocalizedDescriptionKey:description,
            };
            *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier]
                                         code:-1
                                     userInfo:userInfo];
        }
        NSLog(@"error: %@", description);
        
        return NO;
    }
    NSLog(@"writing metadata %@", self);

    MediaMetaDataFileFormatType type = [MediaMetaData fileTypeWithURL:self.location error:error];
    
    if (type == MediaMetaDataFileFormatTypeMP3) {
        return [self writeToMP3FileWithError:error] == 0;
    }
    if (type == MediaMetaDataFileFormatTypeMP4) {
        return [self writeToMP4FileWithError:error] == 0;
    }
    
    NSString* description = [NSString stringWithFormat:@"Unsupported filetype for modifying metadata"];
    if (error) {
        NSDictionary* userInfo = @{
            NSLocalizedDescriptionKey:description,
        };
        *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier]
                                     code:-1
                                 userInfo:userInfo];
    }
    NSLog(@"error: %@", description);
    
    return NO;
}

@end
