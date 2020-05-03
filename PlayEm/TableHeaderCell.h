//
//  TableHeaderCell.h
//  PlayEm
//
//  Created by Till Toenshoff on 19.11.22.
//  Copyright © 2022 Till Toenshoff. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface TableRowView : NSTableRowView
{
    
}

- (void)drawSelectionInRect:(NSRect)dirtyRect;

@end
//
//@interface TableHeaderView : NSTableHeaderView
//{
//    
//}
//
//@end

@interface TableHeaderCell : NSTableHeaderCell
{
}
- (void)drawWithFrame:(CGRect)cellFrame
          highlighted:(BOOL)isHighlighted
               inView:(NSView *)view;
@end




NS_ASSUME_NONNULL_END
