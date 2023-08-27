//
//  ControlPanelController.h
//  PlayEm
//
//  Created by Till Toenshoff on 27.11.22.
//  Copyright © 2022 Till Toenshoff. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class ScrollingTextView;

@protocol ControlPanelControllerDelegate <NSObject>

- (void)showInfo:(id)sender;
- (void)playPause:(id)sender;
- (void)volumeChange:(id)sender;

@end

@interface ControlPanelController : NSTitlebarAccessoryViewController

@property (strong, nonatomic) NSButton* playPause;
@property (strong, nonatomic) NSTextField* duration;
@property (strong, nonatomic) NSTextField* time;
@property (strong, nonatomic) NSTextField* bpm;
@property (strong, nonatomic) ScrollingTextView* titleView;
@property (strong, nonatomic) ScrollingTextView* albumArtistView;
@property (strong, nonatomic) NSButton* coverButton;
@property (strong, nonatomic) NSButton* loop;
@property (strong, nonatomic) NSButton* shuffle;
@property (strong, nonatomic) NSSlider* volumeSlider;
@property (strong, nonatomic) NSLevelIndicator* level;

- (void)loadView;
//- (void)tick;

@end

NS_ASSUME_NONNULL_END
