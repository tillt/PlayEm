//
//  DragImageFileView.m
//  PlayEm
//
//  Created by Till Toenshoff on 14.03.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//

#import "DragImageFileView.h"

@implementation DragImageFileView

- (void)drawRect:(NSRect)dirtyRect
{
    [super drawRect:dirtyRect];

    // Drawing code here.
}

#pragma mark - Drag & Drop

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender
{
    NSPasteboard* pboard = [sender draggingPasteboard];
    NSDragOperation sourceDragMask = [sender draggingSourceOperationMask];

    if ([[pboard types] containsObject:NSPasteboardTypeFileURL]) {
        if (sourceDragMask & NSDragOperationGeneric) {
            return NSDragOperationGeneric;
        } else if (sourceDragMask & NSDragOperationLink) {
            return NSDragOperationLink;
        } else if (sourceDragMask & NSDragOperationCopy) {
            return NSDragOperationCopy;
        }
    }
    return NSDragOperationNone;
}

- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender
{
    return YES;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender
{
    NSPasteboard* pboard = [sender draggingPasteboard];

    if (pboard.pasteboardItems.count <= 1) {
        NSURL* url = [NSURL URLFromPasteboard:pboard];
        if (url) {
            return [_delegate performDragOperationWithURL:url];
        }
    }
    return NO;
}

@end
