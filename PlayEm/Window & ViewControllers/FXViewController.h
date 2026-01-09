//
//  FXViewController.h
//  PlayEm
//
//  Created by Till Toenshoff on 01/07/26.
//  Copyright © 2026 Till Toenshoff. All rights reserved.
//
#import <Cocoa/Cocoa.h>

@class AudioController;

NS_ASSUME_NONNULL_BEGIN

@interface FXViewController : NSWindowController

@property (nonatomic, copy) void (^effectSelectionChanged)(NSInteger index);

- (instancetype)initWithAudioController:(AudioController*)audioController;
- (void)showWithParent:(NSWindow*)parent;
- (void)selectEffectIndex:(NSInteger)index;
- (void)updateEffects:(NSArray<NSDictionary*>*)effects;
- (void)hide;
- (void)setAudioController:(AudioController*)audioController;
- (void)applyCurrentSelection;
- (void)setEffectEnabledState:(BOOL)enabled;

@end

NS_ASSUME_NONNULL_END
