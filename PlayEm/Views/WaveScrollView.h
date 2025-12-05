//
//  WaveScrollView.h
//  PlayEm
//
//  Created by Till Toenshoff on 8/23/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <AppKit/AppKit.h>
#import "WaveView.h"

NS_ASSUME_NONNULL_BEGIN

@interface WaveScrollView : NSScrollView <PlaybackDisplay>

@property (assign, nonatomic) BOOL horizontal;
@property (assign, nonatomic) NSSize tileSize;

@end

NS_ASSUME_NONNULL_END
