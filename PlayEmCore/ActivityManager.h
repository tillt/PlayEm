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
/// Unique identifier for an activity.
@property (nonatomic, strong, readonly) NSUUID* uuid;
@end

@interface ActivityEntry : NSObject
/// Token identifying the activity.
@property (nonatomic, strong, readonly) ActivityToken* token;
/// Display title for the activity.
@property (nonatomic, copy, readonly) NSString* title;
/// Optional detail text.
@property (nonatomic, copy, readonly, nullable) NSString* detail;
/// Progress 0–1; negative means indeterminate.
@property (nonatomic, assign, readonly) double progress;  // <0 indeterminate
/// Whether the activity can be cancelled.
@property (nonatomic, assign, readonly) BOOL cancellable;
/// YES if the activity has completed.
@property (nonatomic, assign, readonly) BOOL completed;
@end

@interface ActivityManager : NSObject

/// Current activity snapshot (read-only).
@property (nonatomic, copy, readonly) NSArray<ActivityEntry*>* activities;

+ (instancetype)shared;

/// Start a new activity and post an update.
///
/// - Parameters:
///   - title: Display title.
///   - detail: Optional detail string.
///   - cancellable: Whether the activity can be cancelled.
///   - cancelHandler: Invoked on cancel requests; may be nil.
- (ActivityToken*)beginActivityWithTitle:(NSString*)title
                                  detail:(nullable NSString*)detail
                             cancellable:(BOOL)cancellable
                           cancelHandler:(nullable dispatch_block_t)cancelHandler;

/// Update progress and/or detail for an activity (async on main).
- (void)updateActivity:(ActivityToken*)token progress:(double)progress detail:(nullable NSString*)detail;

- (void)updateActivity:(ActivityToken*)token progress:(double)progress;

- (void)updateActivity:(ActivityToken*)token detail:(nullable NSString*)detail;

/// Mark an activity complete and emit an update.
- (void)completeActivity:(ActivityToken*)token;

/// Request cancellation; invokes cancelHandler and completes the activity.
- (void)requestCancel:(ActivityToken*)token;

/// Return YES if the activity exists and is not completed.
- (BOOL)isActive:(ActivityToken*)token;

/// Lookup an activity entry by token.
- (ActivityEntry*)activityWithToken:(ActivityToken*)token;

/// Returns YES when at least one activity is still in progress (completed == NO).
- (BOOL)hasOngoingActivity;

@end

NS_ASSUME_NONNULL_END
