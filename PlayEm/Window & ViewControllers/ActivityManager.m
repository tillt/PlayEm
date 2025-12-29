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
@property (nonatomic, strong) dispatch_block_t removalBlock;
@end

@implementation ActivityRecord
@end

@interface ActivityManager ()
@property (nonatomic, strong) NSMutableArray<ActivityRecord*>* records;
@property (nonatomic, copy, readwrite) NSArray<ActivityEntry*>* activities;
@property (nonatomic, assign) BOOL notifyScheduled;
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
    }
    return self;
}

- (void)notifyUpdate
{
    if (_notifyScheduled) {
        return;
    }
    _notifyScheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.notifyScheduled = NO;
        [self emitUpdate];
    });
}

- (void)emitUpdate
{
    self.activities = [self.records copy];
    [[NSNotificationCenter defaultCenter] postNotificationName:ActivityManagerDidUpdateNotification object:self];
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

    __weak typeof(self) weakSelf = self;

    record.removalBlock = dispatch_block_create(0, ^{
        typeof(self) strongSelf = weakSelf;

        if (!strongSelf) {
            return;
        }

        NSInteger index = [strongSelf indexOfToken:record.token];

        if (index != NSNotFound) {
            [strongSelf.records removeObjectAtIndex:index];
            [strongSelf notifyUpdate];
        }
    });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(),
                   record.removalBlock);
}

@end
