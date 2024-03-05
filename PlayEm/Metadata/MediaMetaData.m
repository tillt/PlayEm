//
//  MediaMetaData.m
//  PlayEm
//
//  Created by Till Toenshoff on 08.11.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import "MediaMetaData.h"

#import <AVFoundation/AVFoundation.h>
#import <iTunesLibrary/ITLibArtist.h>
#import <iTunesLibrary/ITLibAlbum.h>
#import <iTunesLibrary/ITLibArtwork.h>

#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>

#import <Foundation/Foundation.h>

#import "MediaMetaData+TagLib.h"
#import "MediaMetaData+AVAsset.h"

///
/// MediaMetaData is lazily holding metadata for library entries to allow for extending iTunes provided data.
/// iTunes provided data are held in a shadow item until data is requested and thus copied in. iTunes metadata
/// is asynchronously requested through ITLibMediaItem on demand.
///

NSString* const kMediaMetaDataMapKeyMP3 = @"mp3";
NSString* const kMediaMetaDataMapKeyMP4 = @"mp4";
NSString* const kMediaMetaDataMapKeyType = @"type";
NSString* const kMediaMetaDataMapKeyKey = @"key";
NSString* const kMediaMetaDataMapKeyKeySpace = @"keySpace";
NSString* const kMediaMetaDataMapKeyKeys = @"keys";
NSString* const kMediaMetaDataMapKeyOrder = @"order";
NSString* const kMediaMetaDataMapTypeString = @"string";
NSString* const kMediaMetaDataMapTypeDate = @"date";
NSString* const kMediaMetaDataMapTypeImage = @"image";
NSString* const kMediaMetaDataMapTypeTuple = @"tuple";
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
    
    if ([fileExtension isEqualToString:@"mp4"] || [fileExtension isEqualToString:@"m4a"]) {
        return MediaMetaDataFileFormatTypeMP4;
    }
    if ([fileExtension isEqualToString:@"mp3"]) {
        return MediaMetaDataFileFormatTypeMP3;
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
                kMediaMetaDataMapKeyKey: @"ALBUM",
            },
            kMediaMetaDataMapKeyMP4: @{
                kMediaMetaDataMapKeyKey: AVMetadataCommonKeyAlbumName,
                kMediaMetaDataMapKeyKeySpace: AVMetadataKeySpaceCommon,
            },
        },
        @"albumArtist": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKeyKey: @"ALBUMARTIST",
            },
            kMediaMetaDataMapKeyMP4: @{
                kMediaMetaDataMapKeyKey: AVMetadataiTunesMetadataKeyAlbumArtist,
                kMediaMetaDataMapKeyKeySpace: AVMetadataKeySpaceiTunes,
            },
        },
        @"artist": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKeyKey: @"ARTIST",
            },
            kMediaMetaDataMapKeyMP4: @{
                kMediaMetaDataMapKeyKey: AVMetadataCommonKeyArtist,
                kMediaMetaDataMapKeyKeySpace: AVMetadataKeySpaceCommon,
            },
        },
        @"artwork": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKeyKey: @"PICTURE",
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeImage,
            },
            kMediaMetaDataMapKeyMP4: @{
                kMediaMetaDataMapKeyKey: AVMetadataCommonKeyArtwork,
                kMediaMetaDataMapKeyKeySpace: AVMetadataKeySpaceCommon,
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeImage,
            },
        },
        @"comment": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKeyKey: @"COMMENT",
            },
            kMediaMetaDataMapKeyMP4: @{
                kMediaMetaDataMapKeyKey: AVMetadataiTunesMetadataKeyUserComment,
                kMediaMetaDataMapKeyKeySpace: AVMetadataKeySpaceiTunes,
            },
        },
        @"composer": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKeyKey: @"COMPOSER",
            },
            kMediaMetaDataMapKeyMP4: @{
                kMediaMetaDataMapKeyKey: AVMetadataiTunesMetadataKeyComposer,
                kMediaMetaDataMapKeyKeySpace: AVMetadataKeySpaceiTunes,
            },
        },
        @"compilation": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKeyKey: @"COMPILATION",
            },
            kMediaMetaDataMapKeyMP4: @{
                kMediaMetaDataMapKeyKey: AVMetadataiTunesMetadataKeyDiscCompilation,
                kMediaMetaDataMapKeyKeySpace: AVMetadataKeySpaceiTunes,
            },
        },
        @"lyrics": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKeyKey: @"LYRICS",
            },
            kMediaMetaDataMapKeyMP4: @{
                kMediaMetaDataMapKeyKey: AVMetadataiTunesMetadataKeyLyrics,
                kMediaMetaDataMapKeyKeySpace: AVMetadataKeySpaceiTunes,
            },
        },
        @"label": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKeyKey: @"LABEL",
            },
            kMediaMetaDataMapKeyMP4: @{
                kMediaMetaDataMapKeyKey: AVMetadataiTunesMetadataKeyRecordCompany,
                kMediaMetaDataMapKeyKeySpace: AVMetadataKeySpaceiTunes,
            },
        },
        @"disk": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKeyKey: @"DISCNUMBER",
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeTuple,
                kMediaMetaDataMapKeyOrder: @0,
            },
            kMediaMetaDataMapKeyMP4: @{
                kMediaMetaDataMapKeyKey: AVMetadataiTunesMetadataKeyDiscNumber,
                kMediaMetaDataMapKeyKeySpace: AVMetadataKeySpaceiTunes,
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeTuple,
                kMediaMetaDataMapKeyOrder: @0,
            },
        },
        @"disks": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKeyKey: @"DISCNUMBER",
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeTuple,
                kMediaMetaDataMapKeyOrder: @1,
            },
            kMediaMetaDataMapKeyMP4: @{
                kMediaMetaDataMapKeyKey: AVMetadataiTunesMetadataKeyDiscNumber,
                kMediaMetaDataMapKeyKeySpace: AVMetadataKeySpaceiTunes,
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeTuple,
                kMediaMetaDataMapKeyOrder: @1,
            },
        },
        @"duration": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKeyKey: @"LENGTH",
            },
        },
        @"genre": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKeyKey: @"GENRE",
            },
            kMediaMetaDataMapKeyMP4: @{
                kMediaMetaDataMapKeyKey: AVMetadataiTunesMetadataKeyUserGenre,
                kMediaMetaDataMapKeyKeySpace: AVMetadataKeySpaceiTunes,
            },
        },
        @"key": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKeyKey: @"INITIALKEY",
            },
        },
        @"tempo": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKeyKey: @"BPM",
            },
            kMediaMetaDataMapKeyMP4: @{
                kMediaMetaDataMapKeyKey: AVMetadataiTunesMetadataKeyBeatsPerMin,
                kMediaMetaDataMapKeyKeySpace: AVMetadataKeySpaceiTunes,
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeNumber,
            },
        },
        @"title": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKeyKey: @"TITLE",
            },
            kMediaMetaDataMapKeyMP4: @{
                kMediaMetaDataMapKeyKey: AVMetadataCommonKeyTitle,
                kMediaMetaDataMapKeyKeySpace: AVMetadataKeySpaceCommon,
            },
        },
        @"track": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKeyKey: @"TRACKNUMBER",
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeTuple,
                kMediaMetaDataMapKeyOrder: @0,
            },
            kMediaMetaDataMapKeyMP4: @{
                kMediaMetaDataMapKeyKey: AVMetadataiTunesMetadataKeyTrackNumber,
                kMediaMetaDataMapKeyKeySpace: AVMetadataKeySpaceiTunes,
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeTuple,
                kMediaMetaDataMapKeyOrder: @0,
            },
        },
        @"tracks": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKeyKey: @"TRACKNUMBER",
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeTuple,
                kMediaMetaDataMapKeyOrder: @1,
            },
            kMediaMetaDataMapKeyMP4: @{
                kMediaMetaDataMapKeyKey: AVMetadataiTunesMetadataKeyTrackNumber,
                kMediaMetaDataMapKeyKeySpace: AVMetadataKeySpaceiTunes,
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeTuple,
                kMediaMetaDataMapKeyOrder: @1,
            },
        },
        @"year": @{
            kMediaMetaDataMapKeyMP3: @{
                kMediaMetaDataMapKeyKey: @"DATE",
                kMediaMetaDataMapKeyType: kMediaMetaDataMapTypeDate,
            },
            kMediaMetaDataMapKeyMP4: @{
                kMediaMetaDataMapKeyKey: AVMetadataiTunesMetadataKeyReleaseDate,
                kMediaMetaDataMapKeyKeySpace: AVMetadataKeySpaceiTunes,
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
            _artworkFormat = [NSNumber numberWithInteger:_shadow.artwork.imageDataFormat];
        } else {
            _artwork = nil;
            _artworkFormat = [NSNumber numberWithInteger:ITLibArtworkFormatNone];
        }
    }
    
    return _artwork;
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
    
    if ([valueObject isKindOfClass:[NSNumber class]] && [valueObject intValue] > 0) {
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

- (BOOL)readFromFileWithError:(NSError**)error
{
    MediaMetaDataFileFormatType type = [MediaMetaData fileTypeWithURL:self.location error:error];
    if (type == MediaMetaDataFileFormatTypeMP3) {
        return [self readFromMP3FileWithError:error] == 0;
    }
    if (type == MediaMetaDataFileFormatTypeMP4) {
        return [self readFromMP4FileWithError:error];
    }
    NSAssert(NO, @"should not have gotten here");
    return NO;
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
        return [self writeToMP4FileWithError:error];
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
