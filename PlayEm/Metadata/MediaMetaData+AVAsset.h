//
//  MediaMetaData+AVAsset.h
//  PlayEm
//
//  Created by Till Toenshoff on 25.02.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import "MediaMetaData.h"

NS_ASSUME_NONNULL_BEGIN

@class AVAsset;

@interface MediaMetaData (AVAsset)

+ (NSDictionary*)id3GenreMap;

- (BOOL)readFromAVAsset:(AVAsset *)asset;
- (BOOL)readFromMP4FileWithError:(NSError**)error;

@end

NS_ASSUME_NONNULL_END
