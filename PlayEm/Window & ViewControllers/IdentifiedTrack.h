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

@interface IdentifiedTrack : NSObject<NSSecureCoding>

@property (copy, nonatomic, nullable) NSString* title;
@property (copy, nonatomic, nullable) NSString* artist;
@property (copy, nonatomic, nullable) NSString* genre;
@property (strong, nonatomic, nullable) NSURL* imageURL;
@property (strong, nonatomic, nullable) NSImage* artwork;
@property (strong, nonatomic, nullable) NSURL* musicURL;
@property (strong, nonatomic, nullable) NSNumber* frame;

- (id)initWithTitle:(NSString*)title
             artist:(NSString*)artist
              genre:(NSString*)genre
           musicURL:(NSURL*)musicURL
           imageURL:(NSURL*)imageURL
              frame:(NSNumber*)frame;

- (id)initWithMatchedMediaItem:(SHMatchedMediaItem*)item;

@end

NS_ASSUME_NONNULL_END
#endif /* IdentifiedTrack_h */
