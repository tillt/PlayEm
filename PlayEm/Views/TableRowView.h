//
//  TableRowView.h
//  PlayEm
//
//  Created by Till Toenshoff on 08.06.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <Quartz/Quartz.h>
#import "TableViewExtraState.h"

NS_ASSUME_NONNULL_BEGIN

@interface TableRowView : NSTableRowView

@property (nonatomic, assign) ExtraState extraState;
@property (nonatomic, strong) CALayer* effectLayer;
@property (nonatomic, strong) CATextLayer* symbolLayer;

- (void)drawSelectionInRect:(NSRect)dirtyRect;

@end

NS_ASSUME_NONNULL_END
