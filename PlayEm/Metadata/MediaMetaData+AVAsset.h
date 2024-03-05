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

- (BOOL)readFromAVAsset:(AVAsset *)asset;
- (NSArray*)renderAVAssetMetaData;

@end

NS_ASSUME_NONNULL_END
