//
//  InfoPanel.h
//  PlayEm
//
//  Created by Till Toenshoff on 15.09.22.
//  Copyright © 2022 Till Toenshoff. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class MediaMetaData;

@protocol InfoPanelControllerDelegate <NSObject>
- (void)metaChanged:(MediaMetaData*)meta;
@end

@interface InfoPanelController : NSViewController <NSTextFieldDelegate>
@property (strong, nonatomic) MediaMetaData* meta;
@property (weak, nonatomic) id<InfoPanelControllerDelegate> delegate;
@end

NS_ASSUME_NONNULL_END
