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
@class MediaMetaData;
@class SymbolButton;

@protocol ControlPanelControllerDelegate <NSObject>

- (void)showInfoForCurrentSong:(id)sender;
- (void)togglePause:(id)sender;
- (void)volumeChange:(id)sender;
- (void)tempoChange:(id)sender;
- (void)resetTempo:(id)sender;

@end

@interface ControlPanelController : NSTitlebarAccessoryViewController

@property (strong, nonatomic) SymbolButton* playPause;
@property (strong, nonatomic) NSTextField* bpm;
@property (strong, nonatomic) NSTextField* beatIndicator;
@property (strong, nonatomic) SymbolButton* loop;
@property (strong, nonatomic) NSButton* shuffle;
@property (strong, nonatomic) NSSlider* volumeSlider;
@property (strong, nonatomic) NSSlider* tempoSlider;
@property (strong, nonatomic) NSLevelIndicator* level;
@property (strong, nonatomic) CIFilter* zoomBlur;
@property (strong, nonatomic) MediaMetaData* meta;

@property (strong, nonatomic) NSProgressIndicator* beatProgress;
@property (strong, nonatomic) NSProgressIndicator* keyProgress;
@property (strong, nonatomic) NSProgressIndicator* autoplayProgress;

@property (assign, nonatomic) BOOL durationUnitTime;


- (id)initWithDelegate:(id<ControlPanelControllerDelegate>)delegate;
- (void)loadView;

- (void)setKey:(NSString*)key hint:(NSString*)hint;
- (void)setKeyHidden:(BOOL)hidden;
- (void)updateDuration:(NSString*)duration time:(NSString*)time;

@end

NS_ASSUME_NONNULL_END
