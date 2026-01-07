//
//  TextViewWithPlaceholder.h
//  PlayEm
//
//  Created by Till Toenshoff on 01.03.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface TextViewWithPlaceholder : NSTextView

@property (strong, nonatomic, nullable) NSAttributedString* placeholderAttributedString;

@end

NS_ASSUME_NONNULL_END
