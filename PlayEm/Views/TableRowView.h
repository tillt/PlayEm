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

/// We allow some extra states for every table row.
///
/// The candidates are: kExtraStatePlaying for obvious reasons,
/// kExtraStateNormal when there is nothing extra and last
/// but not least, kExtraStateActive which is basically just
/// a paused but fully loaded song.
///
/// When setting extra state, we assign it to every single
/// column in that row to make sure it can redraw itself properly.
///
/// Additionally, we show or hide a layer on top of the row
/// that allows us to show an extra symbol on the very left side.
/// Note that we need to assert that the first item in the row does
/// allow for some space for this.
- (void)setExtraState:(ExtraState)extraState;

@end

NS_ASSUME_NONNULL_END
