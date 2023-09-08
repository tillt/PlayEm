//
//  InfoPanel.m
//  PlayEm
//
//  Created by Till Toenshoff on 15.09.22.
//  Copyright © 2022 Till Toenshoff. All rights reserved.
//

#import "InfoPanel.h"
#import "MediaMetaData.h"

@implementation InfoPanelController

- (void)loadView
{
    NSLog(@"loadView");

    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0.0,  0.0, 450.0, 720.0)];

    const CGFloat imageWidth = 400.0f;
    const CGFloat nameFieldWidth = 80.0;
    const CGFloat rowUnitHeight = 18.0f;
    const CGFloat kBorderWidth = 5.0;
    const CGFloat kRowInset = 4.0f;
    const CGFloat kRowSpace = 4.0f;

    CGFloat y = 20.0f;
   
    NSDictionary* config = @{
        @"01 title": @{
            @"width": @340,
        },
        @"02 artist": @{
            @"width": @340,
        },
        @"03 album": @{
            @"width": @340,
        },
        @"04 genre": @{
            @"width": @150,
        },
        @"05 year": @{
            @"width": @60,
        },
        @"06 track": @{
            @"width": @40,
        },
        @"07 disk": @{
            @"width": @40,
        },
        @"08 tempo": @{
            @"width": @40,
        },
        @"09 key": @{
            @"width": @40,
        },
        @"10 location": @{
            @"width": @340,
            @"rows": @2,
        },
    };
    NSMutableDictionary* dict = [NSMutableDictionary dictionary];
    
    NSArray* orderedKeys = [[config allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString* key in [orderedKeys reverseObjectEnumerator]) {
        NSString* name = [key substringFromIndex:3];

        NSNumber* number = config[key][@"width"];
        CGFloat width = [number floatValue];
        unsigned int rows = 1;
        number = [config[key] objectForKey:@"rows"];

        NSTextField* textField = [NSTextField textFieldWithString:name];
        textField.bordered = NO;
        textField.textColor = [NSColor secondaryLabelColor];
        textField.drawsBackground = NO;
        textField.editable = NO;
        textField.alignment = NSTextAlignmentRight;
        textField.frame = NSMakeRect(kBorderWidth,
                                     y - floor((rowUnitHeight - 13.0) / 2.0f),
                                     nameFieldWidth,
                                     (rows * rowUnitHeight) + kRowInset);
        [self.view addSubview:textField];

        textField = [NSTextField textFieldWithString:@""];
        textField.bordered = YES;
        textField.textColor = [NSColor labelColor];
        textField.drawsBackground = NO;
        textField.editable = YES;
        textField.alignment = NSTextAlignmentLeft;

        if (number != nil){
            rows = [number intValue];
            if (rows > 1) {
                textField.lineBreakMode = NSLineBreakByCharWrapping;
                textField.usesSingleLineMode = NO;
                textField.cell.wraps = YES;
                textField.cell.scrollable = NO;
            } else {
                textField.usesSingleLineMode = YES;
            }
        }

        textField.frame = NSMakeRect(nameFieldWidth + kBorderWidth + kBorderWidth,
                                     y,
                                     width - kBorderWidth,
                                     (rows * rowUnitHeight) + kRowInset);
        [self.view addSubview:textField];
        
        dict[name] = textField;

        y += (rows * rowUnitHeight) + kRowInset + kRowSpace;
    }
    _dictionary = dict;

    y += kRowSpace;
    
    _coverView = [NSImageView imageViewWithImage:[NSImage imageNamed:@"UnknownSong"]];
    _coverView.alignment = NSViewHeightSizable | NSViewWidthSizable | NSViewMinYMargin | NSViewMaxYMargin;
    _coverView.imageScaling = NSImageScaleProportionallyUpOrDown;
    _coverView.frame = CGRectMake((self.view.bounds.size.width - imageWidth) / 2.0f ,
                                  y,
                                  imageWidth,
                                  imageWidth);
    [self.view addSubview:_coverView];
}

- (void)setMeta:(MediaMetaData*)meta
{
    _meta = meta;
    
    if (self.view != nil) {
        if (_meta.artwork) {
            _coverView.image = _meta.artwork;
        }
        if (_meta.title) {
            ((NSTextField*)_dictionary[@"title"]).stringValue = _meta.title;
        }
        if (_meta.artist) {
            ((NSTextField*)_dictionary[@"artist"]).stringValue = _meta.artist;
        }
        if (_meta.album) {
            ((NSTextField*)_dictionary[@"album"]).stringValue = _meta.album;
        }
        if (_meta.genre) {
            ((NSTextField*)_dictionary[@"genre"]).stringValue = _meta.genre;
        }
        if (_meta.key) {
            ((NSTextField*)_dictionary[@"key"]).stringValue = _meta.key;
        }
        if (_meta.tempo) {
            ((NSTextField*)_dictionary[@"tempo"]).stringValue = _meta.tempo;
        }
        if (_meta.track > 0) {
            ((NSTextField*)_dictionary[@"track"]).stringValue = [NSString stringWithFormat:@"%ld", _meta.track];
        }
        if (_meta.disk > 0) {
            ((NSTextField*)_dictionary[@"disk"]).stringValue = [NSString stringWithFormat:@"%ld", _meta.disk];
        }
        if (_meta.year > 0) {
            ((NSTextField*)_dictionary[@"year"]).stringValue = [NSString stringWithFormat:@"%ld", _meta.year];
        }
        if (_meta.location) {
            ((NSTextField*)_dictionary[@"location"]).stringValue = [_meta.location.absoluteString stringByRemovingPercentEncoding];
        }
    }
}

@end
