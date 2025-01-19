//
//  IdentifyController.m
//  PlayEm
//
//  Created by Till Toenshoff on 01.12.22.
//  Copyright © 2022 Till Toenshoff. All rights reserved.
//

#import "IdentifyController.h"
#import <WebKit/WebKit.h>
#import <ShazamKit/ShazamKit.h>

#import "AudioController.h"
#import "../Defaults.h"
#import "LazySample.h"
#import "IdentificationCoverView.h"

NSString* const kTitleColumnIdenfifier = @"TitleColumn";
NSString* const kCoverColumnIdenfifier = @"CoverColumn";
NSString* const kButtonColumnIdenfifier = @"ButtonColumn";

NSString* const kSoundCloudQuery = @"https://soundcloud.com/search?q=%@";

const CGFloat kTableRowHeight = 50.0f;

@interface IdentifiedItem : NSObject

@property (copy, nonatomic, nullable) NSString* title;
@property (copy, nonatomic, nullable) NSString* artist;
@property (copy, nonatomic, nullable) NSString* genre;
@property (strong, nonatomic, nullable) NSURL* imageURL;
@property (strong, nonatomic, nullable) NSImage* artwork;
@property (strong, nonatomic, nullable) NSURL* musicURL;

- (id)initWithTitle:(NSString*)title
             artist:(NSString*)artist
              genre:(NSString*)genre
           musicURL:(NSURL*)musicURL
           imageURL:(NSURL*)imageURL;
@end


@interface IdentifyController ()

@property (weak, nonatomic) AudioController* audioController;
@property (strong, nonatomic) SHSession* session;

@property (strong, nonatomic) AVAudioPCMBuffer* stream;

@property (strong, nonatomic) IdentificationCoverView* identificationCoverView;
@property (strong, nonatomic) NSButton* clipButton;
@property (strong, nonatomic) NSButton* scButton;

@property (strong, nonatomic) dispatch_queue_t identifyQueue;

@property (strong, nonatomic) NSMutableArray<IdentifiedItem*>* identifieds;

@property (strong, nonatomic) NSTableView* tableView;
@property (strong, nonatomic, nullable) NSURL* imageURL;

@end


@implementation IdentifiedItem

- (id)initWithTitle:(NSString*)title artist:(NSString*)artist genre:(NSString*)genre musicURL:(NSURL*)musicURL imageURL:(NSURL*)imageURL
{
    self = [super init];
    if (self) {
        _title = title;
        _artist = artist;
        _genre = genre;
        _imageURL = imageURL;
        _musicURL = musicURL;
    }
    return self;
}

@end


@implementation IdentifyController

- (id)initWithAudioController:(AudioController *)audioController
{
    self = [super init];
    if (self) {
        _audioController = audioController;
        dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0);
        _identifyQueue = dispatch_queue_create("PlayEm.IdentifyQueue", attr);
        _identifieds = [NSMutableArray array];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    NSLog(@"viewDidLoad");
}

- (void)AudioControllerPlaybackStateChange:(NSNotification*)notification
{
    NSString* state = notification.object;
    if ([state isEqualToString:kPlaybackStatePaused] ||
        [state isEqualToString:kPlaybackStateEnded]) {
        // By closing the window as soon as the playback ends or gets paused we avoid
        // having to re-init the shazam stream. We assume its ok for the user.
        [self.view.window close];
    }
}

- (void)viewWillAppear
{
    NSLog(@"IdentifyController.view becoming visible");
    [self shazam:self];
    [_identificationCoverView startAnimating];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(AudioControllerPlaybackStateChange:)
                                                 name:kAudioControllerChangedPlaybackStateNotification
                                               object:nil];
}

- (void)viewWillDisappear
{
    NSLog(@"IdentifyController.view becoming invisible");
    [[NSApplication sharedApplication] stopModal];
    [_audioController stopTapping];
    [self reset];

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
    const CGFloat kTitleColumnWidth = 170.0;
    const CGFloat kButtonsColumnWidth = 70.0;

    const CGFloat kBorderWidth = 20.0f;
    const CGFloat kBorderHeight = 0.0f;
    
    //const CGFloat kTitleFontSize = 19.0f;
    
    const CGFloat kCoverViewWidth = 260.0;
    const CGFloat kCoverViewHeight = kCoverViewWidth;
    
    const NSAutoresizingMaskOptions kViewFullySizeable = NSViewHeightSizable | NSViewWidthSizable;
    
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 
                                                         0.0,
                                                         kPopoverWidth,
                                                         kPopoverHeight)];

    CGFloat y = kPopoverHeight - (kCoverViewHeight + kBorderHeight);

    NSScrollView* sv = [[NSScrollView alloc] initWithFrame:NSMakeRect(kBorderWidth + kCoverViewWidth,
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
    //_tableView.backgroundColor = [NSColor blueColor];
    _tableView.autoresizingMask = kViewFullySizeable;
    _tableView.headerView = nil;
    _tableView.columnAutoresizingStyle = NSTableViewNoColumnAutoresizing;
    _tableView.rowHeight = kTableRowHeight;
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

    [self.view addSubview:sv];

    _identificationCoverView = [[IdentificationCoverView alloc] initWithFrame:NSMakeRect(kBorderWidth,
                                                                                         y,
                                                                                         kCoverViewWidth,
                                                                                         kCoverViewHeight)];
    _identificationCoverView.image = [NSImage imageNamed:@"UnknownSong"];
    [self.view addSubview:_identificationCoverView];
}

- (NSString*)queryWithIdentifiedItem:(IdentifiedItem*)item
{
    NSString* artist = item.artist;
    NSString* title = item.title;
    NSString* ret = title;
    if (artist != nil && ![artist isEqualToString:@""]) {
        ret = [NSString stringWithFormat:@"%@ - %@", artist, title];
    }
    return ret;
}

- (void)copyQueryToPasteboard:(id)sender
{
    NSButton* button = sender;
    unsigned long tag = button.tag;
    [[NSPasteboard generalPasteboard] clearContents];
    [[NSPasteboard generalPasteboard] setString:[self queryWithIdentifiedItem:_identifieds[tag]]
                                        forType:NSPasteboardTypeString];
}

- (void)openSoundcloud:(id)sender
{
    NSButton* button = sender;
    unsigned long tag = button.tag;
    NSLog(@"soundcloud button tag %ld", tag);
    
    // FIXME: this may very well be wrong -- however, the amperesand gets correctly replaced,
    // FIXME: when needed -- all the predefined sets dont do that for some reason.
    NSCharacterSet *URLFullCharacterSet = [[NSCharacterSet characterSetWithCharactersInString:@" \"#%/:<>?@[\\]^`{|}&"] invertedSet];
    
    NSString* search = [self queryWithIdentifiedItem:_identifieds[tag]];
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

- (void)musicURLClicked:(id)sender
{
    NSButton* button = sender;
    unsigned long tag = button.tag;
    NSLog(@"music url tag %ld", tag);
    NSURL* musicURL = _identifieds[tag].musicURL;
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

- (void)reset
{
    //_svgView.animator.hidden = NO;
    //_coverView.hidden = YES;
    //_coverView.animator.image = [NSImage imageNamed:@"UnknownSong"];
    _identificationCoverView.hidden = NO;
    _clipButton.animator.alphaValue = 0.0;
    _scButton.animator.alphaValue = 0.0;
}

- (void)shazam:(id)sender
{
    NSLog(@"shazam!");
    [self reset];

    _session = [[SHSession alloc] init];
    _session.delegate = self;

    LazySample* sample = _audioController.sample;
    assert(sample);
    
    AVAudioFrameCount matchWindowFrameCount = kPlaybackBufferFrames;
    AVAudioChannelLayout* layout = [[AVAudioChannelLayout alloc] initWithLayoutTag:kAudioChannelLayoutTag_Mono];
    AVAudioFormat* format = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                                             sampleRate:sample.rate
                                                            interleaved:NO
                                                          channelLayout:layout];
    
    _stream = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:matchWindowFrameCount];
    
//#define DEBUG_TAPPING 1

#ifdef DEBUG_TAPPING
    FILE* fp = fopen("/tmp/debug_tap.out", "wb");
#endif
    [_audioController startTapping:^(unsigned long long offset, float* input, unsigned int frames) {
        dispatch_async(self.identifyQueue, ^{
            [self.stream setFrameLength:frames];
            // TODO: Yikes, this is a total nono -- we are writing to a read-only pointer!
            float* outputBuffer = self.stream.floatChannelData[0];
            for (int i = 0; i < frames; i++) {
                float s = 0.0;
                for (int channel = 0; channel < sample.channels; channel++) {
                    s += input[(sample.channels * i) + channel];
                }
                s /= sample.channels;
                outputBuffer[i] = s;
            }
#ifdef DEBUG_TAPPING
            fwrite(outputBuffer, sizeof(float), frames, fp);
#endif
            [self.session matchStreamingBuffer:self.stream
                                        atTime:[AVAudioTime timeWithSampleTime:offset atRate:sample.rate]];
        });
    }];
}

#pragma mark - Shazam session delegate

- (void)session:(SHSession *)session didFindMatch:(SHMatch *)match
{
    dispatch_async(dispatch_get_main_queue(), ^{
        
        if (match.mediaItems[0].artworkURL != nil && ![match.mediaItems[0].artworkURL.absoluteString isEqualToString:self.imageURL.absoluteString]) {
            NSLog(@"need to re/load the image as the displayed URL %@ wouldnt match the requested URL %@", self.imageURL.absoluteString, match.mediaItems[0].artworkURL.absoluteString);
            IdentifiedItem* item = [[IdentifiedItem alloc] initWithTitle:match.mediaItems[0].title
                                                                  artist:match.mediaItems[0].artist
                                                                   genre:match.mediaItems[0].genres.count ? match.mediaItems[0].genres[0] : @""
                                                                musicURL:match.mediaItems[0].appleMusicURL
                                                                imageURL:match.mediaItems[0].artworkURL];
            self.imageURL = match.mediaItems[0].artworkURL;
            dispatch_async(dispatch_queue_create("AsyncImageQueue", NULL), ^{
                NSImage *image = [[NSImage alloc] initWithContentsOfURL:match.mediaItems[0].artworkURL];
                dispatch_async(dispatch_get_main_queue(), ^{
                    self->_identificationCoverView.image = image;
                    item.artwork = image;
                    
                    [self->_identifieds insertObject:item atIndex:0];

                    [self->_tableView beginUpdates];
                    [self->_tableView insertRowsAtIndexes:[NSIndexSet indexSetWithIndex:0]
                                      withAnimation:NSTableViewAnimationSlideRight];
                    [self->_tableView endUpdates];
                });
            });
        }
    });
}

- (void)session:(SHSession *)session didNotFindMatchForSignature:(SHSignature *)signature error:(nullable NSError *)error
{
    /*
    NSArray<NSString*>* messages = @[   @"... so far, not known ...",
                                        @"... that reminds me of ...",
                                        @"... almost got it but then ...",
                                        @"... crunching hard but so far ...",
                                        @"... dont tell me someone pitched this stuff ...",
                                        @"... heard this the other day ...",
                                        @"... nah, no idea ...",
                                        @"... hah, yeah I think I know this one ...",
                                        @"... darn, I swear that one I know for sure ...",
                                        @"... slipped my mind, knew it the other day ...",
                                        @"... wasnt that done by that dude ...",
                                        @"... wait! what was that again..." ];
    int r = arc4random_uniform((unsigned int)messages.count);
    */

    NSLog(@"didNotFindMatchForSignature - error was: %@", error);
    dispatch_async(dispatch_get_main_queue(), ^{
        [self reset];
        self.identificationCoverView.image = [NSImage imageNamed:@"UnknownSong"];
    });
}

#pragma mark - Table View delegate

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row
{
    return NO;
}

- (NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn*)tableColumn row:(NSInteger)row
{
    NSLog(@"%s -- column:%@ row:%ld", __PRETTY_FUNCTION__, [tableColumn description], row);
    NSView* result = [tableView makeViewWithIdentifier:tableColumn.identifier owner:self];
    
    const CGFloat kArtworkSize = kTableRowHeight;
    const CGFloat kRowHeight = kTableRowHeight;
    
    const CGFloat kSmallFontSize = 11.0;
    const CGFloat kRegularFontSize = 13.0;
    const CGFloat kLargeFontSize = 15.0;

    if (result == nil) {
        assert(_identifieds.count > 0);
        const NSInteger tag = _identifieds.count - 1;
        if ([tableColumn.identifier isEqualToString:kCoverColumnIdenfifier]) {
            NSImageView* view = [[NSImageView alloc] initWithFrame:NSMakeRect(0.0,
                                                                              0.0,
                                                                              kArtworkSize,
                                                                              kRowHeight)];
            view.image = _identifieds[row].artwork;
            result = view;
        } else if ([tableColumn.identifier isEqualToString:kButtonColumnIdenfifier]) {
            NSView* view = [[NSView alloc] initWithFrame:NSMakeRect(  0.0,
                                                                      0.0,
                                                                      tableColumn.width,
                                                                      kRowHeight)];
            NSButton* button = [NSButton buttonWithTitle:@"􀫵"
                                                  target:self
                                                  action:@selector(copyQueryToPasteboard:)];
            button.tag = tag;
            button.font = [NSFont systemFontOfSize:kRegularFontSize];
            button.bordered = NO;
            [button setButtonType:NSButtonTypeMomentaryPushIn];
            button.bezelStyle = NSBezelStyleTexturedRounded;
            button.frame = NSMakeRect( (tableColumn.width - 26.0) / 2.0f,
                                        kRowHeight / 2.0,
                                        kRegularFontSize * 2.0f,
                                        kRowHeight / 2.0);
            [view addSubview:button];

            button = [NSButton buttonWithTitle:@"􀙀"
                                        target:self
                                        action:@selector(openSoundcloud:)];
            button.tag = tag;
            button.font = [NSFont systemFontOfSize:kRegularFontSize];
            button.bordered = NO;
            [button setButtonType:NSButtonTypeMomentaryPushIn];
            button.bezelStyle = NSBezelStyleTexturedRounded;
            button.frame = NSMakeRect(  (tableColumn.width - 26.0) / 2.0f,
                                        0.0,
                                        kRegularFontSize * 2.0f,
                                        kRowHeight / 2.0);
            [view addSubview:button];

            button = [NSButton buttonWithTitle:@"􀣺"
                                        target:self
                                        action:@selector(musicURLClicked:)];
            button.tag = tag;
            button.font = [NSFont systemFontOfSize:kRegularFontSize];
            button.bordered = NO;
            [button setButtonType:NSButtonTypeMomentaryPushIn];
            button.bezelStyle = NSBezelStyleTexturedRounded;
            button.frame = NSMakeRect(  (tableColumn.width + 26.0) / 2.0f,
                                        0.0,
                                        kRegularFontSize * 2.0f,
                                        kRowHeight / 2.0);
            [view addSubview:button];

            result = view;
        } else if ([tableColumn.identifier isEqualToString:kTitleColumnIdenfifier]) {
            NSView* view = [[NSView alloc] initWithFrame:NSMakeRect(  0.0,
                                                                      0.0,
                                                                      tableColumn.width,
                                                                      kRowHeight)];

            NSTextField* tf = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0,
                                                                            33.0,
                                                                            tableColumn.width,
                                                                            kLargeFontSize + 3.0)];
            tf.editable = NO;
            tf.font = [NSFont boldSystemFontOfSize:kLargeFontSize];
            tf.drawsBackground = NO;
            tf.bordered = NO;
            tf.usesSingleLineMode = YES;
            tf.alignment = NSTextAlignmentLeft;
            //tf.backgroundColor = [NSColor blackColor];
            tf.textColor = [[Defaults sharedDefaults] lightBeamColor];
            [tf setStringValue:_identifieds[row].title];
            [view addSubview:tf];
            
            tf = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0,
                                                               kLargeFontSize,
                                                               tableColumn.width,
                                                               kLargeFontSize + 2.0)];
            tf.editable = NO;
            tf.font = [NSFont systemFontOfSize:kSmallFontSize];
            tf.drawsBackground = NO;
            tf.usesSingleLineMode = YES;
            tf.bordered = NO;
            tf.alignment = NSTextAlignmentLeft;
            tf.textColor = [[Defaults sharedDefaults] secondaryLabelColor];
            [tf setStringValue:_identifieds[row].artist];
            [view addSubview:tf];

            tf = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0,
                                                               2.0,
                                                               tableColumn.width,
                                                               kSmallFontSize + 2.0)];
            tf.editable = NO;
            tf.font = [NSFont systemFontOfSize:kSmallFontSize];
            tf.drawsBackground = NO;
            tf.bordered = NO;
            tf.usesSingleLineMode = YES;
            tf.alignment = NSTextAlignmentLeft;
            tf.textColor = [[Defaults sharedDefaults] secondaryLabelColor];
            [tf setStringValue:_identifieds[row].genre];
            [view addSubview:tf];

            result = view;
        }
        result.identifier = tableColumn.identifier;
    }

    return result;
}

#pragma mark - Table View data source

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView
{
    return _identifieds.count;
}

@end
