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

@property (weak, nonatomic) IBOutlet NSWindow* waveWindow;
@property (strong, nonatomic) WaveWindowController* waveController;

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
    // Avoid auto-opening files when running under tests.
    if ([NSProcessInfo processInfo].environment[@"XCTestConfigurationFilePath"] != nil) {
        return NO;
    }

    NSURL* url = [NSURL fileURLWithPath:filename];
    url = [WaveWindowController encodeQueryItemsWithUrl:url frame:0LL playing:YES];
    return [[self waveController] loadDocumentFromURL:url meta:nil];
}

- (void)application:(NSApplication*)application openURLs:(NSArray<NSURL*>*)urls
{
    // Avoid auto-opening files when running under tests.
    if ([NSProcessInfo processInfo].environment[@"XCTestConfigurationFilePath"] != nil) {
        return;
    }

    NSURL* url = [WaveWindowController encodeQueryItemsWithUrl:urls[0] frame:0LL playing:YES];
    [[self waveController] loadDocumentFromURL:url meta:nil];
}

- (void)applicationDidFinishLaunching:(NSNotification*)aNotification
{
    // When running under XCTest we keep the UI hidden to avoid popping windows or
    // a dock icon during headless tests.
    if ([[NSProcessInfo processInfo].environment objectForKey:@"XCTestConfigurationFilePath"] != nil) {
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        return;
    }

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
{}

- (NSMenu*)applicationDockMenu:(NSApplication*)sender
{
    return _waveController.dockMenu;
}

@end
