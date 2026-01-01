//
//  MetaController.h
//  PlayEm
//
//  Created by Till Toenshoff on 12/20/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class MediaMetaData;

@interface MetaController : NSObject

- (void)loadAbortWithCallback:(void (^)(void))callback;
- (void)loadAsyncWithPath:(NSString*)path callback:(void (^)(MediaMetaData*))callback;

@end

NS_ASSUME_NONNULL_END
