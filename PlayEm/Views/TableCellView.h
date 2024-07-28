//
//  TableCellView.h
//  PlayEm
//
//  Created by Till Toenshoff on 08.06.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import <Cocoa/Cocoa.h>

#import "TableViewExtraState.h"

NS_ASSUME_NONNULL_BEGIN

@class CATextLayer;
@class CALayer;

@interface TableCellView : NSTableCellView

@property (nonatomic, strong) CATextLayer* textLayer;
@property (nonatomic, assign) ExtraState extraState;

@end

NS_ASSUME_NONNULL_END
