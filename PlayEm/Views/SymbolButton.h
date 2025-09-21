//
//  SymbolButton.h
//  PlayEm
//
//  Created by Till Toenshoff on 9/21/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface SymbolButton : NSControl

@property (assign, nonatomic) NSControlStateValue state;
@property (copy, nonatomic) NSString* symbolName;
@property (copy, nonatomic) NSString* alternateSymbolName;

@end

NS_ASSUME_NONNULL_END
