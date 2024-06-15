//
//  MediaMetaData+StateAdditions.h
//  PlayEm
//
//  Created by Till Toenshoff on 14.06.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import "MediaMetaData.h"

NS_ASSUME_NONNULL_BEGIN

@interface MediaMetaData (StateAdditions)

@property (assign, nonatomic, readonly) BOOL active;

+ (void)setActiveLocation:(NSURL*)url;

@end

NS_ASSUME_NONNULL_END
