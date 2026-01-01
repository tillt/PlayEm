//
//  ActivityManager.h
//  PlayEm
//
//  Created by Till Toenshoff on 12/28/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const ActivityManagerDidUpdateNotification;

@interface ActivityToken : NSObject
@property (nonatomic, strong, readonly) NSUUID* uuid;
@end

@interface ActivityEntry : NSObject
@property (nonatomic, strong, readonly) ActivityToken* token;
@property (nonatomic, copy, readonly) NSString* title;
@property (nonatomic, copy, readonly, nullable) NSString* detail;
@property (nonatomic, assign, readonly) double progress; // <0 indeterminate
@property (nonatomic, assign, readonly) BOOL cancellable;
@property (nonatomic, assign, readonly) BOOL completed;
@end

@interface ActivityManager : NSObject

@property (nonatomic, copy, readonly) NSArray<ActivityEntry*>* activities;

+ (instancetype)shared;

- (ActivityToken*)beginActivityWithTitle:(NSString*)title
                                  detail:(nullable NSString*)detail
                             cancellable:(BOOL)cancellable
                           cancelHandler:(nullable dispatch_block_t)cancelHandler;

- (void)updateActivity:(ActivityToken*)token
              progress:(double)progress
                detail:(nullable NSString*)detail;

- (void)updateActivity:(ActivityToken*)token
              progress:(double)progress;

- (void)updateActivity:(ActivityToken*)token
                detail:(nullable NSString*)detail;

- (void)completeActivity:(ActivityToken*)token;

- (void)requestCancel:(ActivityToken*)token;

- (BOOL)isActive:(ActivityToken*)token;

- (ActivityEntry*)activityWithToken:(ActivityToken*)token;

// Returns YES when at least one activity is still in progress (completed == NO).
- (BOOL)hasOngoingActivity;

@end

NS_ASSUME_NONNULL_END
