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

@interface InfoPanelController : NSViewController

@property (strong, nonatomic) MediaMetaData* meta;
@property (strong, nonatomic) NSTextField* metaTitle;
@property (strong, nonatomic) NSTextField* metaArtist;
@property (strong, nonatomic) NSTextField* metaAlbum;
@property (strong, nonatomic) NSTextField* metaYear;
@property (strong, nonatomic) NSTextField* metaGenre;
@property (strong, nonatomic) NSTextField* metaBPM;
@property (strong, nonatomic) NSTextField* metaKey;
@property (strong, nonatomic) NSTextField* metaTrack;
@property (strong, nonatomic) NSTextField* metaDisk;
@property (strong, nonatomic) NSTextField* metaLocation;
@property (strong, nonatomic) NSImageView* coverView;

@property (strong, nonatomic) NSDictionary* dictionary;


@end

NS_ASSUME_NONNULL_END
