//
//  AppDelegate.m
//  PlayEm
//
//  Created by Till Toenshoff on 30.03.20.
//  Copyright © 2020 Till Toenshoff. All rights reserved.
//

#import "AppDelegate.h"

#import <AVFoundation/AVFoundation.h>
#import <AppKit/NSOpenPanel.h>

#import "WaveWindowController.h"

@interface AppDelegate ()

@property (weak, nonatomic) IBOutlet NSWindow *waveWindow;
@property (strong, nonatomic) WaveWindowController *waveController;

@end


@implementation AppDelegate

- (WaveWindowController*)waveController
{
    if (_waveController == nil) {
        _waveController = [WaveWindowController new];
    }
    return _waveController;
}

- (BOOL)application:(NSApplication*)sender openFile:(NSString*)filename
{
    NSURL* url = [NSURL fileURLWithPath:filename];
    return [[self waveController] loadDocumentFromURL:[WaveWindowController encodeQueryItemsWithUrl:url frame:0LL playing:YES] meta:nil];
}

- (void)application:(NSApplication*)application openURLs:(NSArray<NSURL*>*)urls
{
    [[self waveController] loadDocumentFromURL:[WaveWindowController encodeQueryItemsWithUrl:urls[0] frame:0LL playing:YES] meta:nil];
}

- (void)applicationDidFinishLaunching:(NSNotification*)aNotification
{
    NSLog(@"%@", [[NSUserDefaults standardUserDefaults] dictionaryRepresentation]);

    [[[self waveController] window] makeKeyAndOrderFront:self];

    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    NSData* bookmark = [userDefaults objectForKey:@"bookmark"];

    NSError* error = nil;
    NSURL* url = [NSURL URLByResolvingBookmarkData:bookmark
                                           options:NSURLBookmarkResolutionWithSecurityScope
                                     relativeToURL:nil
                               bookmarkDataIsStale:nil
                                             error:&error];

    [[self waveController] loadDocumentFromURL:url meta:nil];
}

- (void)applicationWillTerminate:(NSNotification*)aNotification
{
    NSLog(@"%@", [[NSUserDefaults standardUserDefaults] dictionaryRepresentation]);
}

@end
