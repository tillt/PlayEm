//
//  DragImageFileView.h
//  PlayEm
//
//  Created by Till Toenshoff on 14.03.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@protocol DragImageFileViewDelegate <NSObject>
- (BOOL)performDragOperationWithURL:(NSURL*)url;
@end

@interface DragImageFileView : NSImageView
@property (nonatomic, weak) IBOutlet id<DragImageFileViewDelegate> delegate;

@end

NS_ASSUME_NONNULL_END
