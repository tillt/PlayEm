//
//  MediaMetaData+ImageController.h
//  PlayEmCore
//
//  Created by Till Toenshoff on 1/10/26.
//  Copyright © 2026 Till Toenshoff. All rights reserved.
//

#import "MediaMetaData.h"

NS_ASSUME_NONNULL_BEGIN

@interface MediaMetaData (ImageController)

- (void)resolvedArtworkForSize:(CGFloat)size placeholder:(BOOL)placeholder callback:(void (^)(NSImage*))callback;

@end

NS_ASSUME_NONNULL_END
