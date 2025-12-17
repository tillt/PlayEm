//
//  TimedMediaMetaData+ChapterForge.hpp
//  PlayEm
//
//  Created by Till Toenshoff on 12/9/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//
#import <Foundation/Foundation.h>
#import "TimedMediaMetaData.h"
#import "TrackList+ChapterForge.hpp"

NS_ASSUME_NONNULL_BEGIN

typedef NSDictionary<NSString*,NSString*> StructuredMetaData;

extern NSString* const kStructuredMetaTitleKey;
extern NSString* const kStructuredMetaArtistKey;
extern NSString* const kStructuredMetaURLKey;


@class AVAsset;

@interface TimedMediaMetaData (ChapterForge)

- (id)initWithChapteredMetaData:(StructuredMetaData*)structured frame:(NSNumber*)frame;
- (void)updateWithStructuredMeta:(StructuredMetaData*)structured frame:(NSNumber*)frame;

@end

NS_ASSUME_NONNULL_END
