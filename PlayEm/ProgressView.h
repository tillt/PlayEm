//
//  ProgressView.h
//  PlayEm
//
//  Created by Till Toenshoff on 28.12.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@protocol ProgressViewDelegate <NSObject>

- (void)progressSeekTo:(unsigned long long)frame;

@end


@interface ProgressView : NSView

//@property (nonatomic, assign) NSTimeInterval max;
//@property (nonatomic, assign) NSTimeInterval current;
@property (nonatomic, assign) unsigned long long max;
@property (nonatomic, assign) unsigned long long current;
@property (nonatomic, weak) IBOutlet id<ProgressViewDelegate> delegate;

@end

NS_ASSUME_NONNULL_END
