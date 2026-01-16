//
//  BrowserController+DeepScan.h
//  PlayEm
//
//  Created by Till Toenshoff on 2026-01-15.
//  Copyright © 2026 Till Toenshoff. All rights reserved.
//

#import "BrowserController.h"

@class MediaMetaData;

@interface BrowserController (DeepScan)

- (void)startDeepScanSchedulerIfNeeded;
- (void)wakeDeepScanScheduler;
- (void)enqueueReconcileWithCompletion:(void (^)(NSArray<MediaMetaData*>* _Nullable refreshedMetas,
                                                 NSArray<MediaMetaData*>* _Nullable changedMetas,
                                                 NSArray<NSURL*>* missingFiles,
                                                 NSError* _Nullable error))completion;
- (void)beginForegroundDeepScanForURL:(NSURL*)url;
- (void)finishForegroundDeepScanForURL:(NSURL*)url
                              duration:(NSNumber* _Nullable)duration
                                 tempo:(NSNumber* _Nullable)tempo
                                   key:(NSString* _Nullable)key;
- (void)cancelForegroundDeepScanForURL:(NSURL*)url;
- (BOOL)shouldSuppressDeepScanForURL:(NSURL*)url;

@end
