//
//  TotalIdentificationController.h
//  PlayEm
//
//  Created by Till Toenshoff on 12/26/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <ShazamKit/ShazamKit.h>

NS_ASSUME_NONNULL_BEGIN

@class LazySample;
@class ActivityToken;
@class TimedMediaMetaData;

@interface TotalIdentificationController : NSObject<SHSessionDelegate>

- (id)initWithSample:(LazySample*)sample;

- (ActivityToken*)detectTracklistWithCallback:(nonnull void (^)(BOOL, NSError*, NSArray<TimedMediaMetaData*>*))callback;
- (void)abortWithCallback:(void (^)(void))callback;

// Optional reference artist (e.g., mix/producer) to boost matching tracks.
@property (copy, nonatomic, nullable) NSString* referenceArtist;
@property (assign, nonatomic) BOOL debugScoring;
@property (assign, nonatomic) BOOL skipRefinement;

@end

NS_ASSUME_NONNULL_END
