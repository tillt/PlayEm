//
//  LibraryStore.h
//  PlayEm
//
//  Created by Till Toenshoff on 09/03/26.
//  Copyright © 2026 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>

@class MediaMetaData;

NS_ASSUME_NONNULL_BEGIN

/// Lightweight persistence wrapper for caching `MediaMetaData` in SQLite.
/// Keeps the existing in-memory model; intended as a backing store/cache.
@interface LibraryStore : NSObject

/// Designated initializer.
- (instancetype)initWithDatabaseURL:(NSURL*)url;

/// Open or create the database and ensure schema exists.
- (BOOL)open:(NSError**)error;

/// Import a batch of media items (e.g., from ITLibrary) into the store.
/// Existing rows are replaced based on URL.
- (BOOL)importMediaItems:(NSArray<MediaMetaData*>*)items error:(NSError**)error;
- (BOOL)importMediaItems:(NSArray<MediaMetaData*>*)items preferExisting:(BOOL)preferExisting error:(NSError**)error;

/// Asynchronous file import. Completion is invoked on the main queue.
- (void)importFileURLs:(NSArray<NSURL*>*)urls completion:(void (^)(NSArray<MediaMetaData*>* _Nullable metas, NSError* _Nullable error))completion;

/// Reconcile the current library: refresh metadata from disk for existing files,
/// report missing files, track entries that changed, and update the store. Completion on main queue.
- (void)reconcileLibraryWithCompletion:(void (^)(NSArray<MediaMetaData*>* _Nullable refreshedMetas,
                                                 NSArray<MediaMetaData*>* _Nullable changedMetas,
                                                 NSArray<NSURL*>* missingFiles,
                                                 NSError* _Nullable error))completion;

/// Load all cached media items as `MediaMetaData` instances.
- (NSArray<MediaMetaData*>* _Nullable)loadAllMediaItems:(NSError**)error;

/// Returns YES if a track with the given URL already exists in the store.
- (BOOL)hasEntryForURL:(NSURL*)url error:(NSError**)error;

/// Asynchronous removal of entries matching the given URLs. Completion on main queue.
- (void)removeEntriesForURLs:(NSArray<NSURL*>*)urls completion:(void (^)(BOOL success, NSError* _Nullable error))completion;

/// Reset running deep scans to pending (e.g., after restart).
- (BOOL)resetDeepScanRunningState:(NSError**)error;

/// Mark URLs for deep scan with optional priority (0 = low, 1 = high).
- (BOOL)enqueueDeepScanForURLs:(NSArray<NSURL*>*)urls priority:(NSInteger)priority error:(NSError**)error;

/// Returns the next URL that needs deep scanning, or nil when none are pending.
- (NSURL* _Nullable)nextDeepScanURL:(NSError**)error;

/// Mark a URL as actively being scanned.
- (BOOL)markDeepScanRunningForURL:(NSURL*)url error:(NSError**)error;

/// Update deep scan results for a URL and mark completed.
- (BOOL)completeDeepScanForURL:(NSURL*)url
                      duration:(NSNumber* _Nullable)duration
                         tempo:(NSNumber* _Nullable)tempo
                           key:(NSString* _Nullable)key
                         error:(NSError**)error;

/// Mark a deep scan as failed for the given URL.
- (BOOL)markDeepScanFailedForURL:(NSURL*)url reason:(NSString*)reason error:(NSError**)error;
- (NSInteger)deepScanOutstandingCount:(NSError**)error;

@end

NS_ASSUME_NONNULL_END
