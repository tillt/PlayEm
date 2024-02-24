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

@class ITLibMediaItem;
@class AVAsset;

enum {
    MediaMetaDataLocationTypeFile = ITLibMediaItemLocationTypeFile,
    MediaMetaDataLocationTypeURL = ITLibMediaItemLocationTypeURL,
    MediaMetaDataLocationTypeRemote = ITLibMediaItemLocationTypeRemote,
    MediaMetaDataLocationTypeUnknown = ITLibMediaItemLocationTypeUnknown
};

extern NSString* const kMediaMetaDataMapKeyMP3;
extern NSString* const kMediaMetaDataMapKeyType;
extern NSString* const kMediaMetaDataMapKeyKey;
extern NSString* const kMediaMetaDataMapKeyKeys;
extern NSString* const kMediaMetaDataMapKeyOrder;
extern NSString* const kMediaMetaDataMapTypeString;
extern NSString* const kMediaMetaDataMapTypeDate;
extern NSString* const kMediaMetaDataMapTypeImage;
extern NSString* const kMediaMetaDataMapTypeNumbers;

@interface MediaMetaData : NSObject

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

+ (NSArray<NSString*>*)mediaMetaKeys;
+ (NSDictionary<NSString*, NSDictionary<NSString*, NSString*>*>*)mp3TagMap;

- (BOOL)syncToFileWithError:(NSError**)error;
- (BOOL)isEqual:(MediaMetaData*)other forKeys:(NSArray<NSString*>*)keys;

- (NSString* _Nullable)stringForKey:(NSString*)key;
- (void)updateWithKey:(NSString*)key string:(NSString*)string;

@end

NS_ASSUME_NONNULL_END
