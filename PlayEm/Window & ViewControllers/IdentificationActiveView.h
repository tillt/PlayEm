//
//  IdentificationActiveView.h
//  PlayEm
//
//  Created by Till Toenshoff on 10.06.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface IdentificationActiveView : NSView
@property (nonatomic, strong) CALayer* imageLayer;

- (void)startAnimating;
- (void)stopAnimating;

@end

NS_ASSUME_NONNULL_END
