//
//  MediaMetaData.h
//  PlayEm
//
//  Created by Till Toenshoff on 08.11.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <iTunesLibrary/ITLibMediaItem.h>
#import <iTunesLibrary/ITLibArtwork.h>
#import "TrackList.h"

NS_ASSUME_NONNULL_BEGIN

typedef double(^FrameToSeconds)(unsigned long long frame);


@class SHMatchedMediaItem;

///
/// MediaMetaData is lazily holding metadata for library entries to allow for extending iTunes provided data.
/// iTunes provided data are held in a shadow item until data is requested and thus copied in.
///

typedef enum : NSUInteger {
    MediaMetaDataLocationTypeFile = ITLibMediaItemLocationTypeFile,
    MediaMetaDataLocationTypeURL = ITLibMediaItemLocationTypeURL,
    MediaMetaDataLocationTypeRemote = ITLibMediaItemLocationTypeRemote,
    MediaMetaDataLocationTypeUnknown = ITLibMediaItemLocationTypeUnknown
} MediaMetaDataLocationType;

typedef enum : NSUInteger {
    MediaMetaDataFileFormatTypeUnknown,
    MediaMetaDataFileFormatTypeMP3,
    MediaMetaDataFileFormatTypeMP4,
    MediaMetaDataFileFormatTypeWAV,
    MediaMetaDataFileFormatTypeAIFF,
} MediaMetaDataFileFormatType;

extern NSString* const kMediaMetaDataMapKeyMP3;
extern NSString* const kMediaMetaDataMapKeyMP4;
extern NSString* const kMediaMetaDataMapKeyType;
extern NSString* const kMediaMetaDataMapKey;
extern NSString* const kMediaMetaDataMapKeys;
extern NSString* const kMediaMetaDataMapOrder;
extern NSString* const kMediaMetaDataMapIdentifier;
extern NSString* const kMediaMetaDataMapTypeString;
extern NSString* const kMediaMetaDataMapTypeDate;
extern NSString* const kMediaMetaDataMapTypeImage;
extern NSString* const kMediaMetaDataMapTypeTuple;
extern NSString* const kMediaMetaDataMapTypeNumber;

//extern NSString* const kStarSymbol;

@interface MediaMetaData : NSObject<NSCopying, NSSecureCoding>
@property (strong, nonatomic) ITLibMediaItem* shadow;
@property (copy, nonatomic, nullable) NSString* title;
@property (copy, nonatomic, nullable) NSString* album;
@property (copy, nonatomic, nullable) NSString* artist;
@property (copy, nonatomic, nullable) NSString* genre;
@property (copy, nonatomic, nullable) NSNumber* year;
@property (copy, nonatomic, nullable) NSString* comment;
@property (copy, nonatomic, nullable) NSString* composer;
@property (copy, nonatomic, nullable) NSString* albumArtist;
@property (copy, nonatomic, nullable) NSString* label;
@property (copy, nonatomic, nullable) NSNumber* tempo;
@property (copy, nonatomic, nullable) NSString* key;
@property (copy, nonatomic, nullable) NSString* lyrics;
@property (copy, nonatomic, nullable) NSNumber* rating;
@property (copy, nonatomic, nullable) NSString* tags;
@property (copy, nonatomic, nullable) NSNumber* track;
@property (copy, nonatomic, nullable) NSNumber* tracks;
@property (copy, nonatomic, nullable) NSNumber* disk;
@property (copy, nonatomic, nullable) NSNumber* disks;
@property (copy, nonatomic, nullable) NSNumber* locationType;
@property (readonly, nonatomic, nullable) NSString* artworkHash;
@property (strong, nonatomic, nullable) NSData* artwork;
@property (readonly, nonatomic, nullable) NSData* artworkWithDefault;
@property (copy, nonatomic, nullable) NSURL* artworkLocation;
@property (copy, nonatomic, nullable) NSNumber* artworkFormat;
@property (copy, nonatomic, nullable) NSURL* location;
@property (copy, nonatomic, nullable) NSDate* added;
@property (copy, nonatomic, nullable) NSNumber* compilation;
@property (copy, nonatomic, nullable) NSNumber* duration;
@property (copy, nonatomic, nullable) NSString* bitrate;
@property (copy, nonatomic, nullable) NSString* samplerate;
@property (copy, nonatomic, nullable) NSString* size;
@property (copy, nonatomic, nullable) NSString* format;
@property (copy, nonatomic, nullable) NSString* channels;
@property (copy, nonatomic, nullable) NSString* volume;
@property (copy, nonatomic, nullable) NSString* volumeAdjustment;
@property (copy, nonatomic, nullable) NSString* stars;
@property (copy, nonatomic, nullable) NSURL* appleLocation;

@property (readonly, nonatomic, nullable) NSImage* imageFromArtwork;

@property (nonatomic, strong) FrameToSeconds frameToSeconds;

@property (strong, nonatomic, nullable) TrackList* trackList;

- (NSURL*)trackListURL;

- (BOOL)storeTracklistWithError:(NSError**)error;

- (void)recoverTracklistWithCallback:(void (^)(BOOL, NSError*))callback;

- (void)setArtworkFromImage:(NSImage*)image;

- (BOOL)exportTracklistToFile:(NSURL*)url frameEncoder:(FrameToString)encoder error:(NSError *__autoreleasing  _Nullable *)error;
- (NSString*)readableTracklistWithFrameEncoder:(FrameToString)encoder;

+ (MediaMetaData*)mediaMetaDataWithURL:(NSURL*)url error:(NSError**)error;
+ (MediaMetaData*)mediaMetaDataWithITLibMediaItem:(ITLibMediaItem*)item error:(NSError**)error;
+ (MediaMetaData*)mediaMetaDataWithSHMatchedMediaItem:(SHMatchedMediaItem*)item error:(NSError**)error;

+ (NSString*)mimeTypeForArtworkFormat:(ITLibArtworkFormat)format;


+ (NSDictionary<NSString*, NSDictionary*>*)mediaMetaKeyMap;
+ (NSArray<NSString*>*)mediaMetaKeys;
+ (NSArray<NSString*>*)mediaDataKeysWithFileFormatType:(MediaMetaDataFileFormatType)type;

+ (NSString*)mimeTypeForArtworkFormat:(ITLibArtworkFormat)formatNumber;
+ (ITLibArtworkFormat)artworkFormatForData:(NSData*)data;

+ (NSData*)defaultArtworkData;

- (BOOL)isEqualToMediaMetaData:(MediaMetaData*)other;
- (BOOL)isEqualToMediaMetaData:(MediaMetaData*)other atKey:key;

- (NSString* _Nullable)stringForKey:(NSString*)key;
- (void)updateWithKey:(NSString*)key string:(NSString*)string;

- (NSImage*)imageFromArtwork;

- (BOOL)readFromFileWithError:(NSError**)error;
- (BOOL)writeToFileWithError:(NSError**)error;

/// Converts whatever comes in into a MixWheel key value.
+ (NSString* _Nullable)correctedKeyNotation:(NSString* _Nullable)key;

+ (NSString*)starsWithRating:(NSNumber*)rating;
+ (NSArray<NSString*>*)starRatings;
+ (NSDictionary*)starsQuantums;

@end

NS_ASSUME_NONNULL_END
