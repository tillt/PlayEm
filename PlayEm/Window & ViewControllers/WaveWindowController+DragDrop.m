//
//  WaveWindowController+DragDrop.m
//  PlayEm
//
//  Created by Till Toenshoff on 2026-01-15.
//  Copyright © 2026 Till Toenshoff. All rights reserved.
//

#import "WaveWindowController+DragDrop.h"

@implementation WaveWindowController (DragDrop)

- (NSArray<NSURL*>*)mediaFileURLsFromURL:(NSURL*)url
{
    if (url == nil || !url.isFileURL) {
        return @[];
    }

    static NSSet<NSString*>* allowedExtensions = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableSet<NSString*>* extensions = [NSMutableSet set];
        NSArray<NSDictionary*>* docTypes = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDocumentTypes"];
        for (NSDictionary* docType in docTypes) {
            NSArray<NSString*>* typeExtensions = docType[@"CFBundleTypeExtensions"];
            for (NSString* ext in typeExtensions) {
                if (ext.length == 0) {
                    continue;
                }
                [extensions addObject:ext.lowercaseString];
            }
        }
        // We could patch here for defaults or hidden filetype support, but why should we.
        allowedExtensions = [extensions copy];
    });

    NSNumber* isDirectory = nil;
    if (![url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil]) {
        return @[];
    }

    if (![isDirectory boolValue]) {
        NSString* ext = url.pathExtension.lowercaseString;
        return [allowedExtensions containsObject:ext] ? @[ url ] : @[];
    }

    NSMutableArray<NSURL*>* files = [NSMutableArray array];
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSArray<NSURLResourceKey>* keys = @[ NSURLIsDirectoryKey, NSURLIsRegularFileKey ];
    NSDirectoryEnumerator<NSURL*>* enumerator =
        [fileManager enumeratorAtURL:url
          includingPropertiesForKeys:keys
                             options:NSDirectoryEnumerationSkipsHiddenFiles | NSDirectoryEnumerationSkipsPackageDescendants
                        errorHandler:^BOOL(NSURL* _Nonnull errorURL, NSError* _Nonnull error) {
                            NSLog(@"[WaveWindowController] skip %@ due to error: %@", errorURL, error);
                            return YES;
                        }];
    for (NSURL* itemURL in enumerator) {
        NSNumber* isFile = nil;
        if ([itemURL getResourceValue:&isFile forKey:NSURLIsRegularFileKey error:nil] && [isFile boolValue]) {
            NSString* ext = itemURL.pathExtension.lowercaseString;
            if ([allowedExtensions containsObject:ext]) {
                [files addObject:itemURL];
            }
        }
    }
    return files;
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
    NSArray<NSURL*>* droppedURLs =
        [pboard readObjectsForClasses:@[ [NSURL class] ] options:@{ NSPasteboardURLReadingFileURLsOnlyKey : @YES }];
    if (droppedURLs.count == 0) {
        return NO;
    }

    NSMutableArray<NSURL*>* fileURLs = [NSMutableArray array];
    for (NSURL* url in droppedURLs) {
        [fileURLs addObjectsFromArray:[self mediaFileURLsFromURL:url]];
    }
    if (fileURLs.count == 0) {
        return NO;
    }

    // Add everything to the library and play the first item.
    [self.browser importFilesAtURLs:fileURLs];

    NSURL* firstURL = fileURLs.firstObject;
    return [self loadDocumentFromURL:[WaveWindowController encodeQueryItemsWithUrl:firstURL frame:0LL playing:YES] meta:nil];
}

@end
