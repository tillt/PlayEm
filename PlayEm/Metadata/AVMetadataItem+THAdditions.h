//
//  AVMetadataItem+THAdditions.h
//  PlayEm
//
//  Created by Till Toenshoff on 15.09.22.
//  Copyright © 2022 Till Toenshoff. All rights reserved.
//
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AVMetadataItem (THAdditions)

@property (readonly) NSString *keyString;

@end

NS_ASSUME_NONNULL_END
