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
    return [[self waveController] loadDocumentFromURL:[NSURL fileURLWithPath:filename] meta:nil];
}

- (void)application:(NSApplication*)application openURLs:(NSArray<NSURL*>*)urls
{
    [[self waveController] loadDocumentFromURL:urls[0] meta:nil];
}

- (void)applicationDidFinishLaunching:(NSNotification*)aNotification
{
    //NSLog(@"%@", [[NSUserDefaults standardUserDefaults] dictionaryRepresentation]);
    [[[self waveController] window] makeKeyAndOrderFront:self];
}

- (void)applicationWillTerminate:(NSNotification*)aNotification
{
    //NSLog(@"%@", [[NSUserDefaults standardUserDefaults] dictionaryRepresentation]);
}

@end
