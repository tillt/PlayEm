//
//  IdentifyController.h
//  PlayEm
//
//  Created by Till Toenshoff on 01.12.22.
//  Copyright © 2022 Till Toenshoff. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <ShazamKit/ShazamKit.h>
NS_ASSUME_NONNULL_BEGIN

@class AudioController;
@class LazySample;
@class MediaMetaData;
@class TimedMediaMetaData;

@protocol IdentifyViewControllerDelegate <NSObject>

- (void)addTrackToTracklist:(TimedMediaMetaData*)track;

@end

@interface IdentifyViewController : NSViewController <SHSessionDelegate, NSMenuDelegate, NSTableViewDelegate, NSTableViewDataSource>

@property (nonatomic, weak) id <IdentifyViewControllerDelegate> delegate;

- (id)initWithAudioController:(AudioController*)audioController delegate:(id<IdentifyViewControllerDelegate>)delegate;
- (void)setCurrentIdentificationSource:(NSURL*)url;
@end

NS_ASSUME_NONNULL_END
