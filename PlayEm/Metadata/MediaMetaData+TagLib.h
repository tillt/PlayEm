//
//  MediaMetaData+TagLib.h
//  PlayEm
//
//  Created by Till Toenshoff on 24.02.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import "MediaMetaData.h"

NS_ASSUME_NONNULL_BEGIN

@interface MediaMetaData (TagLib)

+ (NSDictionary<NSString*, NSDictionary<NSString*, NSString*>*>*)mp3TagMap;
+ (MediaMetaData*)mediaMetaDataFromMP3FileWithURL:(NSURL*)url error:(NSError**)error;

- (int)readFromMP3FileWithError:(NSError**)error;
- (int)writeToMP3FileWithError:(NSError**)error;
- (int)writeToMP4FileWithError:(NSError**)error;

@end

NS_ASSUME_NONNULL_END
