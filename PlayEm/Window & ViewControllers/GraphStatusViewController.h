//
//  GraphStatusViewController.h
//  PlayEm
//
//  Copyright © 2026 Till Toenshoff. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class AudioController;
@class LazySample;

/// Read-only view showing current audio graph status (rates, latency, effect).
@interface GraphStatusViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate>

/// Designated initializer.
///
/// - Parameters:
///   - audioController: Controller supplying playback status.
///   - sample: Currently loaded sample (may be nil).
- (instancetype)initWithAudioController:(AudioController*)audioController sample:(LazySample*)sample;

/// Refresh displayed values from the audio controller and sample.
- (void)reloadData;
/// Update the sample reference and refresh UI.
- (void)updateSample:(LazySample*)sample;

@end
