//
//  ActivityManager.m
//  PlayEm
//
//  Created by Till Toenshoff on 12/28/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import "ActivityManager.h"

NSNotificationName const ActivityManagerDidUpdateNotification = @"ActivityManagerDidUpdateNotification";

@interface ActivityToken ()
@property (nonatomic, strong, readwrite) NSUUID* uuid;
@end

@implementation ActivityToken
- (instancetype)init
{
    self = [super init];
    if (self) {
        _uuid = [NSUUID UUID];
    }
    return self;
}
@end

@interface ActivityEntry ()
@property (nonatomic, strong, readwrite) ActivityToken* token;
@property (nonatomic, copy, readwrite) NSString* title;
@property (nonatomic, copy, readwrite, nullable) NSString* detail;
@property (nonatomic, assign, readwrite) double progress;
@property (nonatomic, assign, readwrite) BOOL cancellable;
@property (nonatomic, assign, readwrite) BOOL completed;
@end

@implementation ActivityEntry
@end

@interface ActivityRecord : ActivityEntry
@property (nonatomic, copy, nullable) dispatch_block_t cancelHandler;
@property (nonatomic, assign) BOOL completed;
@property (nonatomic, assign) CFAbsoluteTime completedAt;
@end

@implementation ActivityRecord
@end

@interface ActivityManager ()
@property (nonatomic, strong) NSMutableArray<ActivityRecord*>* records;
@property (nonatomic, copy, readwrite) NSArray<ActivityEntry*>* activities;
@property (nonatomic, assign) BOOL notifyScheduled;
@property (nonatomic, assign) CFAbsoluteTime lastEmitTime;
@property (nonatomic, assign) NSTimeInterval minEmitInterval;
@property (nonatomic, strong) NSTimer* pruneTimer;
@property (nonatomic, assign) NSTimeInterval retentionInterval;
@end

@implementation ActivityManager

+ (instancetype)shared
{
    static ActivityManager* shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[ActivityManager alloc] init];
    });
    return shared;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _records = [NSMutableArray array];
        _activities = @[];
        _lastEmitTime = 0;
        _minEmitInterval = 0.1; // seconds
        _retentionInterval = 5.0; // seconds to keep completed entries visible
    }
    return self;
}

// Remove completed records that have outlived the retention window.
- (void)purgeStaleRecords
{
    if (self.records.count == 0) {
        return;
    }
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    NSMutableArray<ActivityRecord*>* filtered = [NSMutableArray arrayWithCapacity:self.records.count];
    for (ActivityRecord* rec in self.records) {
        if (rec.completed && rec.completedAt > 0 && (now - rec.completedAt) > self.retentionInterval) {
            continue;
        }
        [filtered addObject:rec];
    }
    if (filtered.count != self.records.count) {
        self.records = filtered;
    }
}

// Schedule a lightweight, infrequent prune timer when there are completed records.
- (void)schedulePruneIfNeeded
{
    if (self.pruneTimer || self.records.count == 0) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    self.pruneTimer = [NSTimer scheduledTimerWithTimeInterval:self.retentionInterval
                                                       repeats:YES
                                                         block:^(NSTimer * _Nonnull timer) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
            [timer invalidate];
            return;
        }
        [strongSelf purgeStaleRecords];
        strongSelf.activities = [strongSelf.records copy];
        [[NSNotificationCenter defaultCenter] postNotificationName:ActivityManagerDidUpdateNotification
                                                            object:strongSelf];
        if (strongSelf.records.count == 0) {
            [timer invalidate];
            strongSelf.pruneTimer = nil;
        }
    }];
    self.pruneTimer.tolerance = self.retentionInterval * 0.5;
    [[NSRunLoop mainRunLoop] addTimer:self.pruneTimer forMode:NSRunLoopCommonModes];
}

// Throttled notification trigger for state updates.
- (void)notifyUpdate
{
    [self purgeStaleRecords];
    // Shortcut if we already have an update waiting to be sent.
    if (_notifyScheduled) {
        return;
    }
    
    // We now wait with our update for the next dispatch to happen.
    _notifyScheduled = YES;

    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    CFAbsoluteTime elapsed = now - _lastEmitTime;
    NSTimeInterval delay = (elapsed >= _minEmitInterval) ? 0.0 : (_minEmitInterval - elapsed);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        // We can finally send our throttled notification update.
        self.notifyScheduled = NO;
        self.lastEmitTime = CFAbsoluteTimeGetCurrent();
        self.activities = [self.records copy];
        [[NSNotificationCenter defaultCenter] postNotificationName:ActivityManagerDidUpdateNotification
                                                            object:self];
    });
}

- (ActivityToken*)beginActivityWithTitle:(NSString*)title
                                  detail:(nullable NSString*)detail
                             cancellable:(BOOL)cancellable
                           cancelHandler:(nullable dispatch_block_t)cancelHandler
{
    ActivityRecord* record = [ActivityRecord new];
    record.token = [ActivityToken new];
    record.title = title;
    record.detail = detail;
    record.progress = -1.0;
    record.cancellable = cancellable;
    record.completed = NO;
    record.cancelHandler = [cancelHandler copy];
    record.completedAt = 0;

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.records addObject:record];
        [self notifyUpdate];
    });

    return record.token;
}

- (void)updateActivity:(ActivityToken*)token detail:(nullable NSString*)detail
{
    if (![token isKindOfClass:[ActivityToken class]]) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        NSInteger index = [self indexOfToken:token];
        if (index == NSNotFound) {
            return;
        }
        ActivityRecord* record = self.records[(NSUInteger)index];
        if (record.completed) {
            return;
        }
        if (detail != nil) {
            record.detail = detail;
        }
        [self notifyUpdate];
    });
}

- (void)updateActivity:(ActivityToken*)token
              progress:(double)progress
                detail:(nullable NSString*)detail
{
    if (![token isKindOfClass:[ActivityToken class]]) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        NSInteger index = [self indexOfToken:token];
        if (index == NSNotFound) {
            return;
        }
        ActivityRecord* record = self.records[(NSUInteger)index];
        if (record.completed) {
            return;
        }
        record.progress = progress;
        if (detail != nil) {
            record.detail = detail;
        }
        [self notifyUpdate];
    });
}

- (void)updateActivity:(ActivityToken*)token progress:(double)progress
{
    [self updateActivity:token progress:progress detail:nil];
}

- (BOOL)isActive:(ActivityToken*)token
{
    [self activityWithToken:token];
    if (![token isKindOfClass:[ActivityToken class]]) {
        return NO;
    }
    NSInteger index = [self indexOfToken:token];
    if (index == NSNotFound) {
        return NO;
    }
    ActivityRecord* record = self.records[(NSUInteger)index];
    return !record.completed;
}

- (ActivityEntry*)activityWithToken:(ActivityToken*)token
{
    if (![token isKindOfClass:[ActivityToken class]]) {
        return nil;
    }
    NSInteger index = [self indexOfToken:token];
    if (index == NSNotFound) {
        return nil;
    }
    return self.activities[(NSUInteger)index];
}

- (BOOL)hasOngoingActivity
{
    __block BOOL found = NO;
    [self.records enumerateObjectsUsingBlock:^(ActivityRecord * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (!obj.completed) {
            found = YES;
            *stop = YES;
        }
    }];
    return found;
}

- (void)completeActivity:(ActivityToken*)token
{
    if (![token isKindOfClass:[ActivityToken class]]) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        NSInteger index = [self indexOfToken:token];
        if (index == NSNotFound) {
            return;
        }

        ActivityRecord* record = self.records[(NSUInteger)index];
        // If already scheduled for removal, ignore.
        if (record.completed) {
            return;
        }
        [self markCompletedAndScheduleRemoval:record];
        [self notifyUpdate];
    });
}

- (void)requestCancel:(ActivityToken*)token
{
    if (![token isKindOfClass:[ActivityToken class]]) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        NSInteger index = [self indexOfToken:token];
        if (index == NSNotFound) {
            return;
        }
        ActivityRecord* record = self.records[(NSUInteger)index];
        if (record.cancelHandler) {
            record.cancelHandler();
        }
    });
}

#pragma mark - Helpers

- (NSInteger)indexOfToken:(ActivityToken*)token
{
    __block NSInteger found = NSNotFound;

    [self.records enumerateObjectsUsingBlock:^(ActivityRecord* obj, NSUInteger idx, BOOL *stop) {
        if ([obj.token.uuid isEqual:token.uuid]) {
            found = (NSInteger)idx;
            *stop = YES;
        }
    }];
    return found;
}

- (void)markCompletedAndScheduleRemoval:(ActivityRecord*)record
{
    record.completed = YES;
    record.cancellable = NO;

    if (record.progress < 0.0) {
        record.progress = 1.0;
    }
    record.completedAt = CFAbsoluteTimeGetCurrent();

    [self schedulePruneIfNeeded];
}

@end
