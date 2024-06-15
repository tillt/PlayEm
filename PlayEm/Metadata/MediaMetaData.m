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
#import "MediaMetaData+StateAdditions.h"

///
/// MediaMetaData is lazily holding metadata for library entries to allow for extending iTunes provided data.
/// iTunes provided data are held in a shadow item until data is requested and thus copied in. iTunes metadata
/// is asynchronously requested through ITLibMediaItem on demand.
///

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

@implementation MediaMetaData

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
    
    if ([fileExtension isEqualToString:@"mp4"] || [fileExtension isEqualToString:@"m4v"] || [fileExtension isEqualToString:@"m4r"] || [fileExtension isEqualToString:@"m4a"]) {
        return MediaMetaDataFileFormatTypeMP4;
    }
    if ([fileExtension isEqualToString:@"mp3"]) {
        return MediaMetaDataFileFormatTypeMP3;
    }
    if ([fileExtension isEqualToString:@"aif"] || [fileExtension isEqualToString:@"aiff"]) {
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
    meta.location = [url filePathURL];
    [meta readFromFileWithError:error];
    return meta;
}

+ (MediaMetaData*)mediaMetaDataWithURL:(NSURL*)url asset:(AVAsset *)asset error:(NSError**)error
{
    MediaMetaData* meta = [[MediaMetaData alloc] init];
    
    meta.location = url;
    
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
        @"locationType": @{},
        
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
        @"duration": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKey: @"LENGTH",
            },
        },
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
        @"tempo": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKey: @"BPM",
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
        return nil;
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
    NSDictionary* mimeMap = @{
        @(ITLibArtworkFormatJPEG): @"image/jpeg",
        @(ITLibArtworkFormatGIF): @"image/gif",
        @(ITLibArtworkFormatPNG): @"image/png",
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
        if (_shadow.hasArtworkAvailable) {
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
    return [NSString stringWithFormat:@"Title: %@ -- Album: %@ -- Artist: %@ -- Location: %@ -- Address: %p -- Artwork format: %@",
            self.title, self.album, self.artist, self.location, (void*)self, self.artworkFormat];
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
            return NO;
        }
    } else {
        NSString* thisValue = [self stringForKey:key];
        NSString* otherValue = [other stringForKey:key];
        
        if (![thisValue isEqualToString:otherValue]) {
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
    objc_property_t property = class_getProperty(self.class, [key cStringUsingEncoding:NSUTF8StringEncoding]);
    const char * const attrString = property_getAttributes(property);
    const char *typeString = attrString + 1;
    const char *next = NSGetSizeAndAlignment(typeString, NULL, NULL);
    const char *className = typeString + 2;
    next = strchr(className, '"');
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

// The MixWheel is not entirely deterministic, we are trying
// to catch all synonymous scales here additionally to the 24 sectors.
- (NSString*)correctedKeyNotation:(NSString*)key
{
    NSDictionary* mixWheel = @{
        //        G♯ minor/A♭ minor,
        @"Abmin": @"1A",
        @"G#min": @"1A",
        //        B major/C♭ major,
        @"Bmaj":  @"1B",
        @"Cbmaj": @"1B",
        //        D♯ minor/E♭ minor,
        @"Ebmin": @"2A",
        @"D#min": @"2A",
        //        F♯ major/G♭ major,
        @"F#maj": @"2B",
        @"Gbmaj": @"2B",
        //        A♯ minor/B♭ minor.
        @"A#min": @"3A",
        @"Bbmin": @"3A",
        //        C♯ major/D♭ major
        @"C#maj": @"3B",
        @"Dbmaj": @"3B",
        @"Fmin":  @"4A",
        @"Abmaj": @"4B",
        @"Cmin":  @"5A",
        @"Ebmaj": @"5B",
        @"Gmin":  @"6A",
        @"Bbmaj": @"6B",
        @"Dmin":  @"7A",
        @"Fmaj":  @"7B",
        @"Amin":  @"8A",
        @"Cmaj":  @"8B",
        @"Emin":  @"9A",
        @"Gmaj":  @"9B",
        @"Bmin":  @"10A",
        @"Dmaj":  @"10B",
        @"F#min": @"11A",
        @"Amaj":  @"11B",
        @"Dbmin": @"12A",
        @"Emaj":  @"12B",
    };
    
    if (key == nil || key.length == 0) {
        return nil;
    }

    NSArray* properValues = [mixWheel allValues];
    if ([properValues indexOfObject:key] != NSNotFound) {
        return key;
    }
    
    NSString* mappedKey = [mixWheel objectForKey:key];
    if (mappedKey != nil) {
        return mappedKey;
    }

    if (key.length > 1) {
        // Get a possible note specifier.
        NSString* s = [key substringWithRange:NSMakeRange(1,1)];
        // We have seen such monster.
        if ([s isEqualToString:@"o"]) {
            key = [NSString stringWithFormat:@"%@#%@", [key substringToIndex:1], [key substringFromIndex:2]];
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
        _key = [self correctedKeyNotation:_key];
    }
    return ret;
}

- (BOOL)writeToFileWithError:(NSError**)error
{
    if (self.location == nil) {
        NSString* description = @"Cannot sync item back as it lacks a location";
        if (error) {
            NSDictionary* userInfo = @{
                NSLocalizedDescriptionKey: description,
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
    
    NSString* description = [NSString stringWithFormat:@"Unsupport filetype for modifying metadata"];
    if (error) {
        NSDictionary* userInfo = @{
            NSLocalizedDescriptionKey: description,
        };
        *error = [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier]
                                     code:-1
                                 userInfo:userInfo];
    }
    NSLog(@"error: %@", description);
    
    return NO;
}

@end
