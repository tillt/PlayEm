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

@class ITLibMediaItem;
@class AVAsset;


enum {
    MediaMetaDataLocationTypeFile = ITLibMediaItemLocationTypeFile,
    MediaMetaDataLocationTypeURL = ITLibMediaItemLocationTypeURL,
    MediaMetaDataLocationTypeRemote = ITLibMediaItemLocationTypeRemote,
    MediaMetaDataLocationTypeUnknown = ITLibMediaItemLocationTypeUnknown
};

@interface MediaMetaData : NSObject

@property (strong, nonatomic) ITLibMediaItem* shadow;

@property (copy, nonatomic, nullable) NSString* title;
@property (copy, nonatomic, nullable) NSString* album;
@property (copy, nonatomic, nullable) NSString* artist;
@property (copy, nonatomic, nullable) NSString* genre;
@property (assign, nonatomic) NSUInteger year;
@property (copy, nonatomic, nullable) NSString* comment;
@property (assign, nonatomic) NSUInteger tempo;
@property (copy, nonatomic, nullable) NSString* key;
@property (strong, nonatomic, nullable) NSImage* artwork;
@property (assign, nonatomic) NSUInteger track;
@property (assign, nonatomic) NSUInteger tracks;
@property (assign, nonatomic) NSUInteger disk;
@property (assign, nonatomic) NSUInteger disks;
@property (assign, nonatomic) NSUInteger locationType;
@property (strong, nonatomic, nullable) NSURL* location;
@property (strong, nonatomic, nullable) NSDate* added;
@property (assign, nonatomic) NSTimeInterval duration;



//+ (MediaMetaData*)mediaMetaDataWithAVAsset:(AVAsset*)asset error:(NSError**)error;
+ (MediaMetaData*)mediaMetaDataWithURL:(NSURL*)url error:(NSError**)error;
+ (MediaMetaData*)mediaMetaDataWithITLibMediaItem:(ITLibMediaItem*)item error:(NSError**)error;
+ (NSArray<NSString*>*)mediaMetaKeys;

- (NSString* _Nullable)stringForKey:(NSString*)key;

@end

NS_ASSUME_NONNULL_END
