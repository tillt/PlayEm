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

@interface IdentifyController : NSViewController <SHSessionDelegate, NSTableViewDelegate, NSTableViewDataSource>

- (id)initWithAudioController:(AudioController*)audioController;

@end

NS_ASSUME_NONNULL_END
