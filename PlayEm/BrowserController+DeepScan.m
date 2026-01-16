//
//  BrowserController+DeepScan.m
//  PlayEm
//
//  Created by Till Toenshoff on 2026-01-15.
//  Copyright © 2026 Till Toenshoff. All rights reserved.
//

#import "BrowserController+DeepScan.h"

#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

#import "ActivityManager.h"
#import "AudioController.h"
#import "BeatTrackedSample.h"
#import "KeyTrackedSample.h"
#import "LazySample.h"
#import "LibraryStore.h"
#import "MediaMetaData.h"

static NSString* const kDeepScanPausedDefaultsKey = @"deepScanPaused";
static const NSTimeInterval kDeepScanIdleInterval = 8.0;
static NSSet<NSString*>* DeepScanExcludedGenres(void)
{
    static NSSet<NSString*>* excluded = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        excluded = [NSSet setWithArray:@[ @"hoerbuch", @"hoerspiel", @"kids", @"comedy", @"spoken" ]];
    });
    return excluded;
}

@interface BrowserController ()
@property (nonatomic, strong) LibraryStore* libraryStore;
@property (nonatomic, strong) NSMutableArray<MediaMetaData*>* cachedLibrary;
@property (nonatomic, strong) AudioController* deepScanAudioController;
@property (nonatomic, strong) NSMutableArray<NSString*>* tempos;
@property (nonatomic, strong) NSMutableArray<NSString*>* keys;
@property (nonatomic, strong) NSArray<MediaMetaData*>* filteredItems;
@property (nonatomic, weak) NSTableView* songsTable;
@property (nonatomic, weak) NSTableView* temposTable;
@property (nonatomic, weak) NSTableView* keysTable;
@property (strong, nonatomic) dispatch_queue_t deepScanQueue;
@property (strong, nonatomic) dispatch_semaphore_t deepScanWake;
@property (assign, nonatomic) BOOL deepScanStop;
@property (strong, nonatomic) ActivityToken* deepScanToken;
@property (assign, nonatomic) NSInteger deepScanTotalCount;
@property (assign, nonatomic) NSInteger deepScanCompletedCount;
@property (assign, nonatomic) BOOL reconcileRequested;
@property (assign, nonatomic) BOOL reconcileRunning;
@property (copy, nonatomic) void (^reconcileCompletion)(NSArray<MediaMetaData*>* _Nullable refreshedMetas,
                                                        NSArray<MediaMetaData*>* _Nullable changedMetas,
                                                        NSArray<NSURL*>* missingFiles,
                                                        NSError* _Nullable error);
- (void)refreshUIWithLibrary:(NSArray<MediaMetaData*>*)library;
- (NSUInteger)songsRowForMeta:(MediaMetaData*)meta;
- (void)columnsFromMediaItems:(NSArray*)items
                       genres:(NSMutableArray*)genres
                      artists:(NSMutableArray*)artists
                       albums:(NSMutableArray*)albums
                       tempos:(NSMutableArray*)tempos
                         keys:(NSMutableArray*)keys
                      ratings:(NSMutableArray*)ratings
                         tags:(NSMutableArray*)tags;
@end

@implementation BrowserController (DeepScan)

- (NSMutableSet<NSString*>*)foregroundDeepScanURLs
{
    static void* kForegroundDeepScanURLsKey = &kForegroundDeepScanURLsKey;
    NSMutableSet<NSString*>* urls = objc_getAssociatedObject(self, kForegroundDeepScanURLsKey);
    if (urls == nil) {
        urls = [NSMutableSet set];
        objc_setAssociatedObject(self, kForegroundDeepScanURLsKey, urls, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return urls;
}

- (void)beginForegroundDeepScanForURL:(NSURL*)url
{
    if (url == nil) {
        return;
    }
    @synchronized(self) {
        [[self foregroundDeepScanURLs] addObject:url.absoluteString];
    }
    NSError* error = nil;
    if (![self.libraryStore markDeepScanRunningForURL:url error:&error]) {
        NSLog(@"Foreground deep scan: failed to mark running for %@: %@", url, error);
    }
}

- (void)finishForegroundDeepScanForURL:(NSURL*)url
                              duration:(NSNumber* _Nullable)duration
                                 tempo:(NSNumber* _Nullable)tempo
                                   key:(NSString* _Nullable)key
{
    if (url == nil) {
        return;
    }
    @synchronized(self) {
        [[self foregroundDeepScanURLs] removeObject:url.absoluteString];
    }
    BOOL hasResults = (duration != nil || tempo != nil || key != nil);
    if (!hasResults) {
        [self cancelForegroundDeepScanForURL:url];
        return;
    }
    NSError* error = nil;
    if (![self.libraryStore completeDeepScanForURL:url duration:duration tempo:tempo key:key error:&error]) {
        NSLog(@"Foreground deep scan: failed to store results for %@: %@", url, error);
        [self cancelForegroundDeepScanForURL:url];
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        MediaMetaData* updatedMeta = [self updateCachedMetaForURL:url duration:duration tempo:tempo key:key];
        if (updatedMeta == nil || self.songsTable == nil) {
            return;
        }
        [self updateTempoAndKeyFilters];
        NSUInteger row = [self songsRowForMeta:updatedMeta];
        if (row == NSNotFound || row >= (NSUInteger) self.songsTable.numberOfRows) {
            return;
        }
        NSIndexSet* rows = [NSIndexSet indexSetWithIndex:row];
        NSIndexSet* cols = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, self.songsTable.tableColumns.count)];
        [self.songsTable reloadDataForRowIndexes:rows columnIndexes:cols];
    });
}

- (void)cancelForegroundDeepScanForURL:(NSURL*)url
{
    if (url == nil) {
        return;
    }
    @synchronized(self) {
        [[self foregroundDeepScanURLs] removeObject:url.absoluteString];
    }
    NSError* error = nil;
    if (![self.libraryStore enqueueDeepScanForURLs:@[ url ] priority:0 error:&error]) {
        NSLog(@"Foreground deep scan: failed to re-enqueue %@: %@", url, error);
    }
}

- (BOOL)shouldSuppressDeepScanForURL:(NSURL*)url
{
    if (url == nil) {
        return NO;
    }
    @synchronized(self) {
        return [[self foregroundDeepScanURLs] containsObject:url.absoluteString];
    }
}

- (NSString*)deepScanDisplayNameForURL:(NSURL*)url
{
    if (url == nil) {
        return @"";
    }
    NSString* name = url.lastPathComponent;
    return name.length > 0 ? name : url.absoluteString;
}

- (NSTimeInterval)estimatedDurationForKeyDecision:(LazySample*)sample
{
    if (sample == nil) {
        return 0.0;
    }
    double rate = sample.fileSampleRate;
    unsigned long long frames = sample.frames;
    if (rate <= 0.0 || frames == 0) {
        return 0.0;
    }
    return (double) frames / rate;
}

- (BOOL)shouldAnalyzeKeyForSample:(LazySample*)sample
{
    NSTimeInterval duration = [self estimatedDurationForKeyDecision:sample];
    if (duration <= 0.0) {
        return YES;
    }
    return [KeyTrackedSample needsKeyForSampleDuration:duration];
}

- (MediaMetaData* _Nullable)cachedMetaForURL:(NSURL*)url
{
    if (self.cachedLibrary == nil || url == nil) {
        return nil;
    }
    for (MediaMetaData* meta in self.cachedLibrary) {
        if ([meta.location.absoluteString isEqualToString:url.absoluteString]) {
            return meta;
        }
    }
    return nil;
}

- (void)updateDeepScanActivityWithDetail:(NSString*)detail stepProgress:(double)stepProgress
{
    if (self.deepScanToken == nil) {
        return;
    }

    if (self.deepScanTotalCount <= 0) {
        [[ActivityManager shared] updateActivity:self.deepScanToken progress:-1.0 detail:detail];
        return;
    }

    double completed = (double) self.deepScanCompletedCount + stepProgress;
    double progress = completed / (double) self.deepScanTotalCount;
    if (progress < 0.0) {
        progress = 0.0;
    } else if (progress > 1.0) {
        progress = 1.0;
    }

    [[ActivityManager shared] updateActivity:self.deepScanToken progress:progress detail:detail];
}

- (void)updateFilterTable:(NSTableView*)table
               sourceList:(NSMutableArray<NSString*>*)source
               newContent:(NSArray<NSString*>*)newContent
{
    if (table == nil || source == nil || newContent == nil) {
        return;
    }
    if ([source isEqualToArray:newContent]) {
        return;
    }

    NSArray<NSString*>* oldContent = [source copy];
    [source setArray:newContent];

    if (oldContent.count != newContent.count) {
        [table reloadData];
        return;
    }

    NSMutableIndexSet* changedRows = [NSMutableIndexSet indexSet];
    NSUInteger count = newContent.count;
    for (NSUInteger idx = 0; idx < count; idx++) {
        if (![oldContent[idx] isEqualToString:newContent[idx]]) {
            [changedRows addIndex:idx];
        }
    }
    if (changedRows.count == 0) {
        return;
    }
    NSIndexSet* cols = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, table.tableColumns.count)];
    [table reloadDataForRowIndexes:changedRows columnIndexes:cols];
}

- (void)updateTempoAndKeyFilters
{
    if (self.filteredItems == nil) {
        return;
    }
    NSMutableArray<NSString*>* newTempos = [NSMutableArray array];
    NSMutableArray<NSString*>* newKeys = [NSMutableArray array];
    [self columnsFromMediaItems:self.filteredItems
                         genres:nil
                        artists:nil
                         albums:nil
                         tempos:newTempos
                           keys:newKeys
                        ratings:nil
                           tags:nil];

    [self updateFilterTable:self.temposTable sourceList:self.tempos newContent:newTempos];
    [self updateFilterTable:self.keysTable sourceList:self.keys newContent:newKeys];
}

- (void)ensureDeepScanActivityWithDetail:(NSString*)detail stepProgress:(double)stepProgress
{
    NSError* countError = nil;
    NSInteger outstanding = [self.libraryStore deepScanOutstandingCount:&countError];
    if (outstanding < 0) {
        NSLog(@"Deep scan count failed: %@", countError);
        return;
    }

    if (outstanding == 0) {
        if (self.deepScanToken != nil && [[ActivityManager shared] isActive:self.deepScanToken]) {
            [[ActivityManager shared] completeActivity:self.deepScanToken];
        }
        self.deepScanToken = nil;
        self.deepScanTotalCount = 0;
        self.deepScanCompletedCount = 0;
        return;
    }

    if (self.deepScanToken == nil || ![[ActivityManager shared] isActive:self.deepScanToken]) {
        self.deepScanTotalCount = outstanding;
        self.deepScanCompletedCount = 0;
        self.deepScanToken = [[ActivityManager shared] beginActivityWithTitle:NSLocalizedString(@"activity.deep_scan.title", @"Title for deep scan activity")
                                                                      detail:detail
                                                                 cancellable:NO
                                                               cancelHandler:nil];
    } else {
        NSInteger expectedTotal = self.deepScanCompletedCount + outstanding;
        if (expectedTotal > self.deepScanTotalCount) {
            self.deepScanTotalCount = expectedTotal;
        }
    }

    [self updateDeepScanActivityWithDetail:detail stepProgress:stepProgress];
}

- (void)enqueueReconcileWithCompletion:(void (^)(NSArray<MediaMetaData*>* _Nullable refreshedMetas,
                                                 NSArray<MediaMetaData*>* _Nullable changedMetas,
                                                 NSArray<NSURL*>* missingFiles,
                                                 NSError* _Nullable error))completion
{
    if (completion) {
        self.reconcileCompletion = [completion copy];
    }
    self.reconcileRequested = YES;
    [self startDeepScanSchedulerIfNeeded];
    [self ensureDeepScanActivityWithDetail:NSLocalizedString(@"activity.library.reconcile.starting", @"Detail when library reconciliation starts")
                              stepProgress:0.0];
    [self wakeDeepScanScheduler];
}

- (void)boostDeepScanForURL:(NSURL*)url
{
    if (url == nil) {
        return;
    }
    NSError* enqueueError = nil;
    if (![self.libraryStore enqueueDeepScanForURLs:@[ url ] priority:1 error:&enqueueError]) {
        NSLog(@"Deep scan enqueue failed: %@", enqueueError);
        return;
    }
    [self wakeDeepScanScheduler];
}

- (void)startDeepScanSchedulerIfNeeded
{
    if (self.deepScanQueue != nil) {
        return;
    }
    NSLog(@"Deep scan scheduler: starting");
    self.deepScanStop = NO;
    self.deepScanWake = dispatch_semaphore_create(0);
    self.deepScanQueue = dispatch_queue_create("PlayEm.DeepScanQueue", DISPATCH_QUEUE_SERIAL);

    NSError* resetError = nil;
    if (![self.libraryStore resetDeepScanRunningState:&resetError]) {
        NSLog(@"Deep scan reset failed: %@", resetError);
    }

    [self ensureDeepScanActivityWithDetail:NSLocalizedString(@"activity.deep_scan.waiting", @"Detail while waiting for deep scan")
                              stepProgress:0.0];

    BrowserController* __weak weakSelf = self;
    dispatch_async(self.deepScanQueue, ^{
        [weakSelf runDeepScanLoop];
    });
}

- (void)wakeDeepScanScheduler
{
    if (self.deepScanWake != nil) {
        dispatch_semaphore_signal(self.deepScanWake);
    }
}

- (void)runDeepScanLoop
{
    while (!self.deepScanStop) {
        @autoreleasepool {
            if (self.reconcileRequested && !self.reconcileRunning) {
                NSLog(@"Deep scan scheduler: running reconcile task");
                self.reconcileRequested = NO;
                self.reconcileRunning = YES;
                [self performReconcileTask];
                self.reconcileRunning = NO;
                continue;
            }
            if ([[NSUserDefaults standardUserDefaults] boolForKey:kDeepScanPausedDefaultsKey]) {
                NSLog(@"Deep scan scheduler: paused");
                dispatch_semaphore_wait(self.deepScanWake, dispatch_time(DISPATCH_TIME_NOW, (int64_t) (kDeepScanIdleInterval * NSEC_PER_SEC)));
                continue;
            }

            NSError* selectError = nil;
            NSURL* url = [self.libraryStore nextDeepScanURL:&selectError];
            if (url == nil) {
                if (selectError) {
                    NSLog(@"Deep scan select failed: %@", selectError);
                } else {
                    NSLog(@"Deep scan scheduler: no pending items");
                }
                dispatch_semaphore_wait(self.deepScanWake, dispatch_time(DISPATCH_TIME_NOW, (int64_t) (kDeepScanIdleInterval * NSEC_PER_SEC)));
                continue;
            }

            NSError* markError = nil;
            if (![self.libraryStore markDeepScanRunningForURL:url error:&markError]) {
                NSLog(@"Deep scan running mark failed: %@", markError);
                dispatch_semaphore_wait(self.deepScanWake, dispatch_time(DISPATCH_TIME_NOW, (int64_t) (kDeepScanIdleInterval * NSEC_PER_SEC)));
                continue;
            }

            NSLog(@"Deep scan scheduler: scanning %@", url);
            [self performDeepScanForURL:url];
        }
    }
}

- (void)performReconcileTask
{
    [self ensureDeepScanActivityWithDetail:NSLocalizedString(@"activity.library.reconcile.starting", @"Detail when library reconciliation starts")
                              stepProgress:0.0];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSArray<MediaMetaData*>* refreshedMetas = nil;
    __block NSArray<MediaMetaData*>* changedMetas = nil;
    __block NSArray<NSURL*>* missingFiles = nil;
    __block NSError* reconcileError = nil;

    [self.libraryStore reconcileLibraryWithCompletion:^(NSArray<MediaMetaData*>* _Nullable refreshed,
                                                        NSArray<MediaMetaData*>* _Nullable changed,
                                                        NSArray<NSURL*>* missing,
                                                        NSError* _Nullable error) {
        refreshedMetas = refreshed ?: @[];
        changedMetas = changed ?: @[];
        missingFiles = missing ?: @[];
        reconcileError = error;
        dispatch_semaphore_signal(semaphore);
    }];

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    [self updateDeepScanActivityWithDetail:NSLocalizedString(@"activity.library.reconcile.merging", @"Detail while merging reconciliation results")
                              stepProgress:1.0];

    void (^completion)(NSArray<MediaMetaData*>* _Nullable, NSArray<MediaMetaData*>* _Nullable, NSArray<NSURL*>*, NSError* _Nullable) = self.reconcileCompletion;
    self.reconcileCompletion = nil;

    if (completion) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(refreshedMetas, changedMetas, missingFiles, reconcileError);
        });
    }

    self.deepScanCompletedCount = 0;
    self.deepScanTotalCount = 0;
}

- (void)performDeepScanForURL:(NSURL*)url
{
    NSString* displayName = [self deepScanDisplayNameForURL:url];
    NSString* durationFormat = NSLocalizedString(@"activity.deep_scan.duration_format", @"Detail while analyzing duration");
    NSString* tempoFormat = NSLocalizedString(@"activity.deep_scan.tempo_format", @"Detail while analyzing tempo");
    NSString* keyFormat = NSLocalizedString(@"activity.deep_scan.key_format", @"Detail while analyzing key");

    NSError* sampleError = nil;
    LazySample* sample = [[LazySample alloc] initWithPath:url.path error:&sampleError];
    if (sampleError) {
        NSLog(@"Deep scan: failed to open sample %@: %@", url, sampleError);
    }

    MediaMetaData* cachedMeta = [self cachedMetaForURL:url];
    NSString* genre = cachedMeta.genre.length > 0 ? cachedMeta.genre.lowercaseString : @"";
    BOOL isExcludedGenre = [DeepScanExcludedGenres() containsObject:genre];
    BOOL needsTempo = !isExcludedGenre && (cachedMeta == nil || cachedMeta.tempo == nil || cachedMeta.tempo.doubleValue <= 0.0);
    BOOL hasKey = (cachedMeta != nil && cachedMeta.key.length > 0);

    if (sample != nil) {
        if (self.deepScanAudioController == nil) {
            self.deepScanAudioController = [AudioController new];
        }
        if (needsTempo || (!hasKey && !isExcludedGenre)) {
            dispatch_semaphore_t decodeSemaphore = dispatch_semaphore_create(0);
            __block BOOL decodeDone = NO;
            [self.deepScanAudioController decodeAsyncForAnalysisWithSample:sample
                                                          completionQueue:dispatch_get_global_queue(QOS_CLASS_UTILITY, 0)
                                                                  callback:^(BOOL done) {
                                                                      decodeDone = done;
                                                                      dispatch_semaphore_signal(decodeSemaphore);
                                                                  }];
            dispatch_semaphore_wait(decodeSemaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t) (60 * NSEC_PER_SEC)));
            if (!decodeDone) {
                NSLog(@"Deep scan: decode timed out for %@", url);
            }
        }
    }

    BOOL needsKey = sample != nil && !hasKey && !isExcludedGenre && [self shouldAnalyzeKeyForSample:sample];
    NSInteger stepCount = 1 + (sample != nil ? 1 : 0) + (needsKey ? 1 : 0);
    NSInteger stepIndex = 0;

    [self ensureDeepScanActivityWithDetail:[NSString localizedStringWithFormat:durationFormat, displayName]
                              stepProgress:stepCount > 0 ? (double) stepIndex / (double) stepCount : 0.0];
    NSNumber* duration = [self resolvedDurationForURL:url];
    stepIndex += 1;

    NSNumber* tempo = nil;
    NSString* key = nil;
    if (sample != nil) {
        if (needsTempo) {
            [self updateDeepScanActivityWithDetail:[NSString localizedStringWithFormat:tempoFormat, displayName]
                                      stepProgress:stepCount > 0 ? (double) stepIndex / (double) stepCount : 0.0];
            tempo = [self resolvedTempoForSample:sample];
            stepIndex += 1;
        }

        if (needsKey) {
            [self updateDeepScanActivityWithDetail:[NSString localizedStringWithFormat:keyFormat, displayName]
                                      stepProgress:stepCount > 0 ? (double) stepIndex / (double) stepCount : 0.0];
            key = [self resolvedKeyForSample:sample];
            stepIndex += 1;
        }
    }

    if (key.length == 0) {
        key = nil;
    }
    if (tempo != nil && tempo.doubleValue <= 0.0) {
        tempo = nil;
    }

    BOOL hasResults = (duration != nil || tempo != nil || key != nil);
    NSError* updateError = nil;
    if (hasResults) {
        if (![self.libraryStore completeDeepScanForURL:url duration:duration tempo:tempo key:key error:&updateError]) {
            NSLog(@"Deep scan update failed: %@", updateError);
            return;
        }
    } else {
        NSString* reason = @"No deep metadata available";
        if (![self.libraryStore markDeepScanFailedForURL:url reason:reason error:&updateError]) {
            NSLog(@"Deep scan failure mark failed: %@", updateError);
        }
        NSString* failedFormat = NSLocalizedString(@"activity.deep_scan.failed_format", @"Detail when deep scan fails");
        self.deepScanCompletedCount += 1;
        [self updateDeepScanActivityWithDetail:[NSString localizedStringWithFormat:failedFormat, displayName]
                                  stepProgress:1.0];
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        MediaMetaData* updatedMeta = [self updateCachedMetaForURL:url duration:duration tempo:tempo key:key];
        if (updatedMeta == nil || self.songsTable == nil) {
            return;
        }
        [self updateTempoAndKeyFilters];
        NSUInteger row = [self songsRowForMeta:updatedMeta];
        if (row == NSNotFound || row >= (NSUInteger) self.songsTable.numberOfRows) {
            return;
        }
        NSIndexSet* rows = [NSIndexSet indexSetWithIndex:row];
        NSIndexSet* cols = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, self.songsTable.tableColumns.count)];
        [self.songsTable reloadDataForRowIndexes:rows columnIndexes:cols];
    });

    self.deepScanCompletedCount += 1;
    //NSString* completedDetail = NSLocalizedString(@"activity.deep_scan.completed", @"Detail when deep scan completes");
    //[self ensureDeepScanActivityWithDetail:completedDetail stepProgress:1.0];
}

- (NSNumber* _Nullable)resolvedDurationForURL:(NSURL*)url
{
    if (url == nil) {
        return nil;
    }
    AVURLAsset* asset = [AVURLAsset URLAssetWithURL:url options:@{AVURLAssetPreferPreciseDurationAndTimingKey : @YES}];
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block AVKeyValueStatus status = AVKeyValueStatusUnknown;
    __block NSError* error = nil;
    [asset loadValuesAsynchronouslyForKeys:@[ @"duration" ]
                         completionHandler:^{
                             status = [asset statusOfValueForKey:@"duration" error:&error];
                             dispatch_semaphore_signal(semaphore);
                         }];
    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t) (30 * NSEC_PER_SEC)));

    if (status != AVKeyValueStatusLoaded || error) {
        if (error) {
            NSLog(@"Deep scan: duration load failed for %@: %@", url, error);
        }
        return nil;
    }

    CMTime durationTime = asset.duration;
    if (!CMTIME_IS_NUMERIC(durationTime)) {
        return nil;
    }

    double seconds = CMTimeGetSeconds(durationTime);
    if (!isfinite(seconds) || seconds <= 0.0) {
        return nil;
    }
    return @(seconds * 1000.0);
}

- (NSNumber* _Nullable)resolvedTempoForSample:(LazySample*)sample
{
    BeatTrackedSample* beatSample = [[BeatTrackedSample alloc] initWithSample:sample];
    beatSample.suppressActivity = YES;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block BOOL ready = NO;
    [beatSample trackBeatsAsyncWithCompletionQueue:dispatch_get_global_queue(QOS_CLASS_UTILITY, 0) callback:^(BOOL done) {
        ready = done;
        dispatch_semaphore_signal(semaphore);
    }];
    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t) (60 * NSEC_PER_SEC)));

    if (!ready) {
        return nil;
    }
    float tempo = [beatSample averageTempo];
    NSLog(@"resolved tempo for sample: %.0f", tempo);
    return tempo > 0.0f ? @(tempo) : nil;
}

- (NSString* _Nullable)resolvedKeyForSample:(LazySample*)sample
{
    if (![self shouldAnalyzeKeyForSample:sample]) {
        return nil;
    }
    KeyTrackedSample* keySample = [[KeyTrackedSample alloc] initWithSample:sample];
    keySample.suppressActivity = YES;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block BOOL ready = NO;
    [keySample trackKeyAsyncWithCompletionQueue:dispatch_get_global_queue(QOS_CLASS_UTILITY, 0) callback:^(BOOL done) {
        ready = done;
        dispatch_semaphore_signal(semaphore);
    }];
    dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t) (60 * NSEC_PER_SEC)));

    if (!ready) {
        return nil;
    }
    return keySample.key;
}

- (MediaMetaData* _Nullable)updateCachedMetaForURL:(NSURL*)url
                                          duration:(NSNumber* _Nullable)duration
                                             tempo:(NSNumber* _Nullable)tempo
                                               key:(NSString* _Nullable)key
{
    if (self.cachedLibrary == nil || url == nil) {
        return nil;
    }
    for (MediaMetaData* meta in self.cachedLibrary) {
        if (![meta.location.absoluteString isEqualToString:url.absoluteString]) {
            continue;
        }
        if (duration != nil) {
            meta.duration = duration;
        }
        if (tempo != nil) {
            meta.tempo = tempo;
        }
        if (key != nil) {
            meta.key = key;
        }
        return meta;
    }
    return nil;
}

@end
