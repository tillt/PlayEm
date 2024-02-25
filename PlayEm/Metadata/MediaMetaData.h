//
//  MediaMetaData.h
//  PlayEm
//
//  Created by Till Toenshoff on 08.11.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <iTunesLibrary/ITLibMediaItem.h>

NS_ASSUME_NONNULL_BEGIN

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
extern NSString* const kMediaMetaDataMapKeyType;
extern NSString* const kMediaMetaDataMapKeyKey;
extern NSString* const kMediaMetaDataMapKeyKeys;
extern NSString* const kMediaMetaDataMapKeyOrder;
extern NSString* const kMediaMetaDataMapTypeString;
extern NSString* const kMediaMetaDataMapTypeDate;
extern NSString* const kMediaMetaDataMapTypeImage;
extern NSString* const kMediaMetaDataMapTypeNumbers;

@interface MediaMetaData : NSObject<NSCopying>


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
@property (copy, nonatomic, nullable) NSNumber* track;
@property (copy, nonatomic, nullable) NSNumber* tracks;
@property (copy, nonatomic, nullable) NSNumber* disk;
@property (copy, nonatomic, nullable) NSNumber* disks;
@property (copy, nonatomic, nullable) NSNumber* locationType;
@property (strong, nonatomic, nullable) NSImage* artwork;
@property (strong, nonatomic, nullable) NSURL* location;
@property (strong, nonatomic, nullable) NSDate* added;
@property (copy, nonatomic, nullable) NSNumber* duration;

+ (MediaMetaData*)mediaMetaDataWithURL:(NSURL*)url error:(NSError**)error;
+ (MediaMetaData*)mediaMetaDataWithITLibMediaItem:(ITLibMediaItem*)item error:(NSError**)error;

+ (NSDictionary<NSString*, NSDictionary*>*)mediaMetaKeyMap;
+ (NSArray<NSString*>*)mediaMetaKeys;
+ (NSArray<NSString*>*)mediaDataKeysWithFileFormatType:(MediaMetaDataFileFormatType)type;

- (BOOL)isEqualToMediaMetaData:(MediaMetaData*)other;

- (NSString* _Nullable)stringForKey:(NSString*)key;
- (void)updateWithKey:(NSString*)key string:(NSString*)string;

- (BOOL)readFromFileWithError:(NSError**)error;
- (BOOL)writeToFileWithError:(NSError**)error;
@end

NS_ASSUME_NONNULL_END
