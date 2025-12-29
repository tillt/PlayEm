//
//  IdentifyController.m
//  PlayEm
//
//  Created by Till Toenshoff on 01.12.22.
//  Copyright © 2022 Till Toenshoff. All rights reserved.
//

#import "IdentifyViewController.h"
#import <WebKit/WebKit.h>
#import <ShazamKit/ShazamKit.h>

#import "AudioController.h"
#import "../Defaults.h"
#import "LazySample.h"
#import "IdentificationCoverView.h"
#import "../NSImage+Resize.h"
#import "../NSImage+Average.h"
#import "ImageController.h"

#import "TimedMediaMetaData.h"
#import "MediaMetaData.h"

NSString* const kTitleColumnIdenfifier = @"TitleColumn";
NSString* const kCoverColumnIdenfifier = @"CoverColumn";
NSString* const kButtonColumnIdenfifier = @"ButtonColumn";

NSString* const kSoundCloudQuery = @"https://soundcloud.com/search?q=%@";
NSString* const kBeatportQuery = @"https://beatport.com/search?q=%@";

const CGFloat kTableRowHeight = 52.0f;


@interface IdentifyViewController ()

@property (weak, nonatomic) AudioController* audioController;
@property (strong, nonatomic) SHSession* session;
@property (assign, nonatomic) unsigned long long sessionFrame;

@property (strong, nonatomic) AVAudioPCMBuffer* stream;

@property (strong, nonatomic) IdentificationCoverView* identificationCoverView;

@property (strong, nonatomic) dispatch_queue_t identifyQueue;

@property (strong, nonatomic) NSMutableArray<TimedMediaMetaData*>* identifieds;

@property (strong, nonatomic) NSTableView* tableView;
@property (strong, nonatomic, nullable) NSURL* imageURL;

@property (strong, nonatomic) NSVisualEffectView* effectBelowList;

@property (strong, nonatomic) NSColor* titleColor;
@property (strong, nonatomic) NSColor* artistColor;
@property (strong, nonatomic) NSColor* genreColor;

@property (strong, nonatomic) NSFont* titleFont;
@property (strong, nonatomic) NSFont* artistFont;
@property (strong, nonatomic) NSFont* genreFont;

@property (assign, nonatomic) CGFloat titleFontSize;
@property (assign, nonatomic) CGFloat artistFontSize;
@property (assign, nonatomic) CGFloat genreFontSize;

@property (strong, nonatomic) NSURL* sampleLocation;

@end


@implementation IdentifyViewController

+ (NSTextField*)textFieldWithFrame:(NSRect)frame font:(NSFont*)font color:(NSColor*)color
{
    NSTextField* title = [[NSTextField alloc] initWithFrame:frame];
    title.editable = NO;
    title.font = font;
    title.drawsBackground = NO;
    title.bordered = NO;
    title.usesSingleLineMode = YES;
    title.cell.truncatesLastVisibleLine = YES;
    title.cell.lineBreakMode = NSLineBreakByTruncatingTail;
    title.alignment = NSTextAlignmentLeft;
    title.textColor = color;
    return title;
}

- (id)initWithAudioController:(AudioController*)audioController delegate:(id<IdentifyViewControllerDelegate>)delegate
{
    self = [super init];
    if (self) {
        _delegate = delegate;
        _audioController = audioController;
        dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0);
        _identifyQueue = dispatch_queue_create("PlayEm.IdentifyQueue", attr);
        _identifieds = [NSMutableArray array];
        _sampleLocation = nil;

        _titleFont = [[Defaults sharedDefaults] largeFont];
        _titleFontSize = [[Defaults sharedDefaults] largeFontSize];
        _titleColor = [[Defaults sharedDefaults] lightFakeBeamColor];
        
        _artistFont = [[Defaults sharedDefaults] smallFont];
        _artistFontSize = [[Defaults sharedDefaults] smallFontSize];
        _artistColor = [[Defaults sharedDefaults] regularFakeBeamColor];

        _genreFont = [[Defaults sharedDefaults] smallFont];
        _genreFontSize = [[Defaults sharedDefaults] smallFontSize];
        _genreColor = [[Defaults sharedDefaults] secondaryLabelColor];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.view.wantsLayer = YES;
    self.view.layer.masksToBounds = NO;
}

- (void)AudioControllerPlaybackStateChange:(NSNotification*)notification
{
    NSString* state = notification.object;
    BOOL playing = [state isEqualToString:kPlaybackStatePlaying];
    // By closing the window as soon as the playback ends or gets paused we avoid
    // having to re-init the shazam stream. We assume its ok for the user.
    if (!playing) {
        [_identificationCoverView pauseAnimating];
    }
    [_identificationCoverView setStill:!playing animated:YES];
    if (playing) {
        [_identificationCoverView startAnimating];
        [self shazam:self];
    }
}

- (void)setCurrentIdentificationSource:(NSURL*)url
{
    if ([_sampleLocation isEqualTo:url]) {
        return;
    }
    _identifieds = [NSMutableArray array];
    _sampleLocation = url;
    [self.tableView reloadData];
    [self updateCoverData:nil animated:YES];
}

- (void)viewWillAppear
{
    [self updateCoverData:nil animated:NO];
    
    [_identificationCoverView setStill:!_audioController.playing animated:NO];
    [_identificationCoverView startAnimating];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(AudioControllerPlaybackStateChange:)
                                                 name:kAudioControllerChangedPlaybackStateNotification
                                               object:nil];
    [self shazam:self];
}

- (void)viewDidDisappear
{
}

- (void)viewWillDisappear
{
    NSLog(@"IdentifyController.view becoming invisible");
    [[NSApplication sharedApplication] stopModal];
    [_audioController stopTapping];
    
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:kAudioControllerChangedPlaybackStateNotification
                                                  object:nil];
}

- (void)loadView
{
    NSLog(@"loadView");
    
    const CGFloat kPopoverWidth = 640.0f;
    const CGFloat kPopoverHeight = 280.0f;
    
    const CGFloat kTableViewWidth = 340.0f;
    
    const CGFloat kCoverColumnWidth = kTableRowHeight;
    const CGFloat kTitleColumnWidth = 238.0;
    const CGFloat kButtonsColumnWidth = 12.0;
    
    const CGFloat kBorderWidth = 20.0f;
    const CGFloat kBorderHeight = 0.0f;
    
    const CGFloat kCoverViewWidth = 260.0;
    const CGFloat kCoverViewHeight = kCoverViewWidth + 30.0;
    
    const NSAutoresizingMaskOptions kViewFullySizeable = NSViewHeightSizable | NSViewWidthSizable;
    
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0.0,
                                                         0.0,
                                                         kPopoverWidth,
                                                         kPopoverHeight)];
    _effectBelowList = [[NSVisualEffectView alloc] initWithFrame:NSMakeRect(kCoverViewWidth + kBorderWidth + kBorderWidth,
                                                                            0,
                                                                            kTableViewWidth + kBorderWidth + kBorderWidth,
                                                                            kPopoverHeight+30.0)];
    _effectBelowList.material = NSVisualEffectMaterialMenu;
    _effectBelowList.autoresizingMask = NSViewHeightSizable | NSViewMinXMargin;
    _effectBelowList.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    
    CGFloat y = (kPopoverHeight + 12.0) - (kCoverViewHeight + kBorderHeight);
    
    NSScrollView* sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(0,
                                                                      y,
                                                                      kTableViewWidth,
                                                                      kCoverViewHeight)];
    sv.hasVerticalScroller = YES;
    sv.autoresizingMask = kViewFullySizeable;
    sv.automaticallyAdjustsContentInsets = YES;
    sv.drawsBackground = NO;
    
    self.tableView = [[NSTableView alloc] initWithFrame:NSMakeRect(0.0,
                                                                   0.0,
                                                                   kTableViewWidth,
                                                                   kCoverViewHeight)];
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.backgroundColor = [NSColor clearColor];
    _tableView.allowsEmptySelection = NO;
    _tableView.autoresizingMask = kViewFullySizeable;
    _tableView.headerView = nil;
    _tableView.columnAutoresizingStyle = NSTableViewNoColumnAutoresizing;
    _tableView.rowHeight = kTableRowHeight + 2.0;
    _tableView.intercellSpacing = NSMakeSize(0.0, 0.0);
    
    NSTableColumn* col = [[NSTableColumn alloc] init];
    col.title = @"";
    col.identifier = kCoverColumnIdenfifier;
    col.width = kCoverColumnWidth;
    [_tableView addTableColumn:col];
    
    col = [[NSTableColumn alloc] init];
    col.title = @"";
    col.identifier = kTitleColumnIdenfifier;
    col.width = kTitleColumnWidth;
    [_tableView addTableColumn:col];
    
    col = [[NSTableColumn alloc] init];
    col.title = @"";
    col.identifier = kButtonColumnIdenfifier;
    col.width = kButtonsColumnWidth;
    [_tableView addTableColumn:col];
    
    sv.documentView = _tableView;
    
    [_effectBelowList addSubview:sv];
    
    // This better be square
    _identificationCoverView = [[IdentificationCoverView alloc] initWithFrame:NSMakeRect(0,
                                                                                         0,
                                                                                         kCoverViewWidth + kBorderWidth + kBorderWidth,
                                                                                         kPopoverHeight+20.0)
                                                               contentsInsets:NSEdgeInsetsMake(kBorderWidth,kBorderWidth, 20.0,kBorderWidth)
                                                                        style:CoverViewStyleGlowBehindCoverAtLaser
                                | CoverViewStyleSepiaForSecondImageLayer
                                | CoverViewStylePumpingToTheBeat
                                | CoverViewStyleRotatingLaser];

    [self.view addSubview:_identificationCoverView];
    [self.view addSubview:_effectBelowList];
}

- (NSString*)queryWithIdentifiedTrack:(TimedMediaMetaData*)item
{
    NSString* artist = item.meta.artist;
    NSString* title = item.meta.title;
    NSString* ret = title;
    if (artist != nil && ![artist isEqualToString:@""]) {
        ret = [NSString stringWithFormat:@"%@ - %@", artist, title];
    }
    return ret;
}

- (NSMenu*)itemMenuForTag:(int)tag
{
    NSMenu* menu = [NSMenu new];
    NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:@"Add to Track List"
                                                  action:@selector(addToTrackList:)
                                           keyEquivalent:@""];
    [item setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    item.tag = tag;
    [menu addItem:item];

    [menu addItem:[NSMenuItem separatorItem]];

    item = [[NSMenuItem alloc] initWithTitle:@"Copy to Clipboard"
                                              action:@selector(copyQueryToPasteboard:)
                                           keyEquivalent:@""];
    [item setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    item.tag = tag;
    [menu addItem:item];

    [menu addItem:[NSMenuItem separatorItem]];

    item = [[NSMenuItem alloc] initWithTitle:@"Open in Soundcloud"
                                      action:@selector(openSoundcloud:)
                               keyEquivalent:@""];
    [item setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    item.tag = tag;
    [menu addItem:item];

    item = [[NSMenuItem alloc] initWithTitle:@"Open in Beatport"
                                      action:@selector(openBeatport:)
                               keyEquivalent:@""];
    [item setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    item.tag = tag;
    [menu addItem:item];

    item = [menu addItemWithTitle:@"Open in Apple Music"
                           action:@selector(musicURLClicked:)
                    keyEquivalent:@""];
    item.tag = tag;
    item.target = self;
    
    return menu;
}

- (void)showMenu:(id)sender
{
    NSButton* button = sender;
    NSMenu* menu = [self itemMenuForTag:(int)button.tag];
    NSPoint mouseLocation = [NSEvent mouseLocation];

    [menu popUpMenuPositioningItem:menu.itemArray[0]
                        atLocation:NSMakePoint(mouseLocation.x - 12.0f, mouseLocation.y + 12.0f)
                            inView:nil];
}

- (void)addToTrackList:(id)sender
{
    NSButton* button = sender;
    unsigned long row = (_identifieds.count - button.tag) - 1;
    TimedMediaMetaData* track = _identifieds[row];
    NSLog(@"identified: %@", track);
    //NSTimeInterval time = [_audioController.sample timeForFrame:track.frame];
    [_delegate addTrackToTracklist:track];
}

- (void)copyQueryToPasteboard:(id)sender
{
    NSButton* button = sender;
    unsigned long row = (_identifieds.count - button.tag) - 1;
    NSLog(@"requested query from row: %ld", row);
    NSLog(@"identified: %@", _identifieds[row]);
    [[NSPasteboard generalPasteboard] clearContents];
    [[NSPasteboard generalPasteboard] setString:[self queryWithIdentifiedTrack:_identifieds[row]]
                                        forType:NSPasteboardTypeString];
}

- (void)openSoundcloud:(id)sender
{
    NSButton* button = sender;
    NSLog(@"soundcloud button tag: %ld", button.tag);
    unsigned long row = (_identifieds.count - button.tag) - 1;
    NSLog(@"soundcloud button row: %ld", row);
    
    // FIXME: this may very well be wrong -- however, the amperesand gets correctly replaced,
    // FIXME: when needed -- all the predefined sets dont do that for some reason.
    NSCharacterSet *URLFullCharacterSet = [[NSCharacterSet characterSetWithCharactersInString:@" \"#%/:<>?@[\\]^`{|}&"] invertedSet];
    
    NSString* search = [self queryWithIdentifiedTrack:_identifieds[row]];
    search = [search stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    search = [search stringByAddingPercentEncodingWithAllowedCharacters:URLFullCharacterSet];
    
    NSURL* queryURL = [NSURL URLWithString:[NSString stringWithFormat:kSoundCloudQuery, search]];
    NSURL* appURL = [[NSWorkspace sharedWorkspace] URLForApplicationToOpenURL:queryURL];
    NSWorkspaceOpenConfiguration* configuration = [NSWorkspaceOpenConfiguration new];
    [[NSWorkspace sharedWorkspace] openURLs:[NSArray arrayWithObject:queryURL]
                       withApplicationAtURL:appURL
                              configuration:configuration
                          completionHandler:^(NSRunningApplication* app, NSError* error){
    }];
}

- (void)openBeatport:(id)sender
{
    NSButton* button = sender;
    unsigned long row = (_identifieds.count - button.tag) - 1;
    NSLog(@"beatport button row %ld", row);
    
    // FIXME: this may very well be wrong -- however, the amperesand gets correctly replaced,
    // FIXME: when needed -- all the predefined sets dont do that for some reason.
    NSCharacterSet *URLFullCharacterSet = [[NSCharacterSet characterSetWithCharactersInString:@" \"#%/:<>?@[\\]^`{|}&"] invertedSet];
    
    NSString* search = [self queryWithIdentifiedTrack:_identifieds[row]];
    search = [search stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    search = [search stringByAddingPercentEncodingWithAllowedCharacters:URLFullCharacterSet];
    
    NSURL* queryURL = [NSURL URLWithString:[NSString stringWithFormat:kBeatportQuery, search]];
    NSURL* appURL = [[NSWorkspace sharedWorkspace] URLForApplicationToOpenURL:queryURL];
    NSWorkspaceOpenConfiguration* configuration = [NSWorkspaceOpenConfiguration new];
    [[NSWorkspace sharedWorkspace] openURLs:[NSArray arrayWithObject:queryURL]
                       withApplicationAtURL:appURL
                              configuration:configuration
                          completionHandler:^(NSRunningApplication* app, NSError* error){
    }];
}

- (void)musicURLClicked:(id)sender
{
    NSButton* button = sender;
    unsigned long row = (_identifieds.count - button.tag) - 1;
    NSLog(@"music url row %ld", row);
    NSURL* musicURL = _identifieds[row].meta.appleLocation;
    //    NSLog(@"opening %@", _musicURL);
    // For making sure this wont open Music.app we fetch the
    // default app for URLs.
    // With that we explicitly call the browser for opening the
    // URL. That way we get things displayed even in cases where
    // Music.app does not show iCloud.Music.
    NSURL* appURL = [[NSWorkspace sharedWorkspace] URLForApplicationToOpenURL:musicURL];
    NSWorkspaceOpenConfiguration* configuration = [NSWorkspaceOpenConfiguration new];
    [[NSWorkspace sharedWorkspace] openURLs:[NSArray arrayWithObject:musicURL]
                       withApplicationAtURL:appURL
                              configuration:configuration
                          completionHandler:^(NSRunningApplication* app, NSError* error){
    }];
}

- (void)shazam:(id)sender
{
    NSLog(@"shazam!");
    
    _session = [[SHSession alloc] init];
    _session.delegate = self;
    
    SampleFormat sampleFormat = _audioController.sample.sampleFormat;

    AVAudioFrameCount matchWindowFrameCount = kPlaybackBufferFrames;
    AVAudioChannelLayout* layout = [[AVAudioChannelLayout alloc] initWithLayoutTag:kAudioChannelLayoutTag_Mono];
    AVAudioFormat* format = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                                             sampleRate:sampleFormat.rate
                                                            interleaved:NO
                                                          channelLayout:layout];
    
    _stream = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:matchWindowFrameCount];
    
#ifdef DEBUG_TAPPING
    FILE* fp = fopen("/tmp/debug_tap.out", "wb");
#endif
    
    __weak IdentifyViewController* weakSelf = self;
    
    [_audioController startTapping:^(unsigned long long offset, float* input, unsigned int frames) {
        if (weakSelf == nil) {
            NSLog(@"weak reference gone");
            return;
        }
        dispatch_async(weakSelf.identifyQueue, ^{
            [weakSelf.stream setFrameLength:frames];
            // TODO: Yikes, this is a total nono -- we are writing to a read-only pointer!
            float* outputBuffer = weakSelf.stream.floatChannelData[0];
            for (int i = 0; i < frames; i++) {
                float s = 0.0;
                for (int channel = 0; channel < sampleFormat.channels; channel++) {
                    s += input[(sampleFormat.channels * i) + channel];
                }
                s /= sampleFormat.channels;
                outputBuffer[i] = s;
            }
#ifdef DEBUG_TAPPING
            fwrite(outputBuffer, sizeof(float), frames, fp);
#endif
            weakSelf.sessionFrame = offset;

            AVAudioTime* time = [AVAudioTime timeWithSampleTime:offset atRate:sampleFormat.rate];
            [weakSelf.session matchStreamingBuffer:self.stream atTime:time];
        });
    }];
}

#pragma mark - Shazam session delegate

- (void)updateCoverData:(NSData* _Nullable)data animated:(BOOL)animated
{
    [self->_identificationCoverView setImage:[NSImage resizedImageWithData:data
                                                                      size:self->_identificationCoverView.frame.size]
                                    animated:animated];
}

- (void)session:(SHSession *)session didFindMatch:(SHMatch *)match
{
    __weak IdentifyViewController* weakSelf = self;

    dispatch_async(dispatch_get_main_queue(), ^{
        IdentifyViewController* strongSelf = weakSelf;

        if (match.mediaItems[0].artworkURL != nil &&
            ![match.mediaItems[0].artworkURL.absoluteString isEqualToString:weakSelf.imageURL.absoluteString]) {
            NSLog(@"need to re/load the image as the displayed URL %@ wouldnt match the requested URL %@", strongSelf.imageURL.absoluteString, match.mediaItems[0].artworkURL.absoluteString);
            
            TimedMediaMetaData* track = [[TimedMediaMetaData alloc] initWithMatchedMediaItem:match.mediaItems[0]
                                                                                      frame:[NSNumber numberWithUnsignedLongLong:weakSelf.sessionFrame]];

            NSLog(@"track starts at frame: %@", track.frame);

            
            void (^continuation)(void) = ^(void) {
                IdentifyViewController* strongSelf = weakSelf;

                strongSelf.imageURL = match.mediaItems[0].artworkURL;
                [strongSelf updateCoverData:track.meta.artwork animated:YES];

                [strongSelf->_identifieds insertObject:track atIndex:0];
                [strongSelf->_tableView beginUpdates];
                NSIndexSet* indexSet = [NSIndexSet indexSetWithIndex:0];
                [strongSelf->_tableView insertRowsAtIndexes:indexSet
                                        withAnimation:NSTableViewAnimationSlideRight];
                [strongSelf->_tableView endUpdates];
            };
            
            if (track.meta.artwork != nil) {
                continuation();
            } else {
                if (track.meta.artworkLocation != nil) {
                    [[ImageController shared] resolveDataForURL:track.meta.artworkLocation callback:^(NSData* data){
                        track.meta.artwork = data;
                        continuation();
                    }];
                }
            }
        }
    });
}

- (void)session:(SHSession *)session didNotFindMatchForSignature:(SHSignature *)signature error:(nullable NSError *)error
{
    NSLog(@"didNotFindMatchForSignature - error was: %@", error);
    dispatch_async(dispatch_get_main_queue(), ^{
        //[self->_tableView selectRowIndexes:[NSIndexSet indexSet] byExtendingSelection:NO];
        if (self->_identifieds.count > 0) {
            TimedMediaMetaData* lastTrack = self->_identifieds[0];

            if (lastTrack.meta.artworkLocation == nil && lastTrack.meta.appleLocation == nil) {
                NSLog(@"unknown already on top, no need to add more");
                return;
            }
        }
        
        TimedMediaMetaData* item = [TimedMediaMetaData unknownTrackAtFrame:[NSNumber numberWithUnsignedLongLong:self.sessionFrame]];

        NSLog(@"item frame: %@", item.frame);
        [self updateCoverData:nil animated:YES];

        [self->_identifieds insertObject:item atIndex:0];

        [self->_tableView beginUpdates];
        NSIndexSet* indexSet = [NSIndexSet indexSetWithIndex:0];
        [self->_tableView insertRowsAtIndexes:indexSet
                                withAnimation:NSTableViewAnimationSlideRight];
        [self->_tableView endUpdates];
    });
}

#pragma mark - Table View delegate

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row
{
    return NO;
}

- (nullable NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(nullable NSTableColumn*)tableColumn row:(NSInteger)row
{
    NSLog(@"%s -- column:%@ row:%ld", __PRETTY_FUNCTION__, [tableColumn description], row);
    NSView* result = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
    
    NSString* const buttonTitle = @"􀍠";

    const CGFloat kArtworkSize = kTableRowHeight - 2.0;

    
    assert(_identifieds.count > 0);
    
    TimedMediaMetaData* track = _identifieds[row];
    
    const NSInteger tag = (_identifieds.count - 1) - row;
    if ([tableColumn.identifier isEqualToString:kCoverColumnIdenfifier]) {
        NSImageView* imageView = nil;
        if (result == nil) {
            imageView = [[NSImageView alloc] initWithFrame:NSMakeRect(0.0,
                                                                      0.0,
                                                                      kArtworkSize,
                                                                      kArtworkSize)];
            result = imageView;
        } else {
            imageView = (NSImageView*)result;
        }
        imageView.identifier = tableColumn.identifier;

        imageView.image = [NSImage resizedImageWithData:_identifieds[row].meta.artworkWithDefault
                                           size:NSMakeSize(kArtworkSize, kArtworkSize)];
        
        __weak NSImageView *weakView = imageView;
        __weak NSTableView *weakTable = tableView;

        if (_identifieds[row].meta.artwork != nil) {
            [[ImageController shared] imageForData:track.meta.artwork
                                               key:track.meta.artworkHash
                                              size:imageView.frame.size.width
                                        completion:^(NSImage *image) {
                if (image == nil || weakView == nil || weakTable == nil) {
                    return;
                }
                if ([weakTable rowForView:weakView] == row) {
                    weakView.image = image;
                }
            }];
        }
    } else if ([tableColumn.identifier isEqualToString:kButtonColumnIdenfifier]) {
        NSButton* menuButton = nil;
        if (result == nil) {
            NSView* view = [[NSView alloc] initWithFrame:NSMakeRect(0.0,
                                                                    0.0,
                                                                    tableColumn.width,
                                                                    kArtworkSize)];
            menuButton = [NSButton buttonWithTitle:buttonTitle
                                            target:self
                                            action:@selector(showMenu:)];
            menuButton.font = [NSFont systemFontOfSize:[[Defaults sharedDefaults] normalFontSize]];
            menuButton.bordered = NO;
            [menuButton setButtonType:NSButtonTypeMomentaryPushIn];
            menuButton.bezelStyle = NSBezelStyleTexturedRounded;
            menuButton.frame = NSMakeRect(0.0,
                                          roundf((kArtworkSize - roundf(kArtworkSize / 2.0)) / 2.0),
                                          tableColumn.width,
                                          roundf(kArtworkSize / 2.0));
            [view addSubview:menuButton];
            result = view;
        } else {
            NSArray<NSButton*>* subviews = [result subviews];
            menuButton = subviews[0];
        }
        result.identifier = tableColumn.identifier;

        menuButton.tag = tag;
    } else if ([tableColumn.identifier isEqualToString:kTitleColumnIdenfifier]) {
        NSTextField* title = nil;
        NSTextField* artist = nil;
        NSTextField* genre = nil;
        if (result == nil) {
            NSView* view = [[NSView alloc] initWithFrame:NSMakeRect(  0.0,
                                                                    0.0,
                                                                    tableColumn.width,
                                                                    kArtworkSize)];
            
            title = [IdentifyViewController textFieldWithFrame:NSMakeRect(  0.0,
                                                                          ((_artistFontSize + 4.0) * 2.0),
                                                                          tableColumn.width,
                                                                          _titleFontSize + 3.0)
                                                          font:_titleFont
                                                         color:_titleColor];
            [view addSubview:title];
            
            artist = [IdentifyViewController textFieldWithFrame:NSMakeRect( 0.0,
                                                                           (_artistFontSize + 2.0) + 3.0,
                                                                           tableColumn.width,
                                                                           _artistFontSize + 2.0)
                                                           font:_artistFont
                                                          color:_artistColor];
            [view addSubview:artist];
            
            genre = [IdentifyViewController textFieldWithFrame:NSMakeRect( 0.0,
                                                                          2.0,
                                                                          tableColumn.width,
                                                                          _genreFontSize + 2.0)
                                                          font:_genreFont
                                                         color:_genreColor];
            [view addSubview:genre];
            
            result = view;
        } else {
            NSArray<NSTextField*>* subviews = result.subviews;
            title = subviews[0];
            artist = subviews[1];
            genre = subviews[2];
        }
        result.identifier = tableColumn.identifier;
        [title setStringValue:track.meta.title != nil ? track.meta.title : @""];
        [artist setStringValue:track.meta.artist != nil ? track.meta.artist : @""];
        [genre setStringValue:track.meta.genre != nil ? track.meta.genre : @""];
    }
    
    return result;
}

#pragma mark - Table View data source

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView
{
    return _identifieds.count;
}

@end
