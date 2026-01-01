//
//  MediaMetaData+ChapterForge.hpp
//  PlayEm
//
//  Created by Till Toenshoff on 12/9/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import "TrackList+ChapterForge.hpp"
#import "MediaMetaData.h"
NS_ASSUME_NONNULL_BEGIN

typedef NSDictionary<NSString*,NSString*> StructuredMetaData;

@class AVAsset;

@interface MediaMetaData (ChapterForge)

+ (MediaMetaData*)mediaMetaDataWithStructuredMeta:(StructuredMetaData*)structured;

- (BOOL)writeChaperMarksToMP4FileWithError:(NSError**)error;
- (void)updateWithStructuredMeta:(StructuredMetaData*)structured;

@end

NS_ASSUME_NONNULL_END
