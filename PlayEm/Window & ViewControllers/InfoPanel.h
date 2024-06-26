//
//  InfoPanel.h
//  PlayEm
//
//  Created by Till Toenshoff on 15.09.22.
//  Copyright © 2022 Till Toenshoff. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "DragImageFileView.h"

NS_ASSUME_NONNULL_BEGIN

@class MediaMetaData;

@protocol InfoPanelControllerDelegate <NSObject>
- (NSArray<NSString*>*)knownGenres;
- (void)metaChangedForMeta:(MediaMetaData *)meta updatedMeta:(MediaMetaData *)updatedMeta;
- (void)finalizeMetaUpdates;
@end

@interface InfoPanelController : NSViewController <NSTextFieldDelegate, NSTextViewDelegate, NSTabViewDelegate, NSComboBoxDataSource, NSComboBoxDelegate, DragImageFileViewDelegate>
@property (weak, nonatomic) id<InfoPanelControllerDelegate> delegate;
@property (assign, nonatomic) BOOL processCurrentSong;

- (id)initWithMetas:(NSArray<MediaMetaData*>*)metas;

@end

NS_ASSUME_NONNULL_END
