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

/// Add a detected track to the tracklist.
///
/// - Parameter track: Identified track metadata.
- (void)addTrackToTracklist:(TimedMediaMetaData*)track;

@end

@interface IdentifyViewController : NSViewController <SHSessionDelegate, NSMenuDelegate, NSTableViewDelegate, NSTableViewDataSource>

@property (nonatomic, weak) id<IdentifyViewControllerDelegate> delegate;

/// Create an identification view controller bound to an audio controller.
///
/// - Parameters:
///   - audioController: Audio controller providing playback and tap data.
///   - delegate: Receiver for identified tracks.
- (id)initWithAudioController:(AudioController*)audioController delegate:(id<IdentifyViewControllerDelegate>)delegate;
/// Set the current identification source URL and refresh displayed results.
///
/// - Parameter url: Location of the audio being identified.
- (void)setCurrentIdentificationSource:(NSURL*)url;
@end

NS_ASSUME_NONNULL_END
