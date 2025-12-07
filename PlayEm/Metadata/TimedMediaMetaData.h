//
//  IdentifiedTrack.h
//  PlayEm
//
//  Created by Till Toenshoff on 9/27/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//
#import <Foundation/Foundation.h>

#ifndef IdentifiedTrack_h
#define IdentifiedTrack_h

NS_ASSUME_NONNULL_BEGIN

@class SHMatchedMediaItem;
@class MediaMetaData;

@interface TimedMediaMetaData : NSObject<NSSecureCoding>

+ (TimedMediaMetaData*)unknownTrackAtFrame:(NSNumber*)frame;

@property (strong, nonatomic, nullable) NSNumber* frame;
@property (strong, nonatomic, nullable) MediaMetaData* meta;

- (id)initWithMatchedMediaItem:(SHMatchedMediaItem*)item frame:(NSNumber*)frame;
- (id)initWithTimedMediaGroup:(AVTimedMetadataGroup*)group framerate:(long)rate;

@end

NS_ASSUME_NONNULL_END
#endif /* IdentifiedTrack_h */
