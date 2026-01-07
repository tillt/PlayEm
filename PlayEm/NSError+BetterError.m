//
//  NSError+BetterError.h
//  PlayEm
//
//  Created by Till Toenshoff on 27.02.24.
//  Copyright © 2024 Till Toenshoff. All rights reserved.
//
#import <AudioToolbox/AudioToolbox.h>
#include <ctype.h>

#import "NSError+BetterError.h"

@implementation NSError (BetterError)

+ (NSString*)stringFromOSStatus:(NSInteger)code
{
    const int length = 4;
    char cString[length + 1];

    for (int i = 0; i < length; i++) {
        int shift = (length - (i + 1)) * 8;
        int component = (code >> shift) & 0xFF;
        if (component == 0 || !isascii(component)) {
            return nil;
        }
        cString[i] = component;
    }
    cString[length] = 0;

    return [NSString stringWithCString:cString encoding:NSStringEncodingConversionAllowLossy];
}

/// Adding extended, human readable information to macOS system errors.
///
/// - Parameters:
///   - error: original error object
///
/// - Returns: enhanced error object wrapping the origina
///
+ (NSError*)betterErrorWithError:(NSError*)error
{
    return [NSError betterErrorWithError:error action:nil url:nil];
}

/// Adding extended, human readable information to macOS system errors.
///
/// - Parameters:
///   - error: original error object
///   - url: location of the resource connected to the given action
///
/// - Returns: enhanced error object wrapping the origina
///
+ (NSError*)betterErrorWithError:(NSError*)error url:(NSURL*)url
{
    return [NSError betterErrorWithError:error action:nil url:url];
}

/// Adding extended, human readable information to macOS system errors.
///
/// - Parameters:
///   - error: original error object
///   - action: text describing the action that resultet in the given error
///   - url: location of the resource connected to the given action
///
/// - Returns: enhanced error object wrapping the origina
///
///  It is a dicy game passing a system error to a user. Usually the user wont
///  be able to "fix" the problem which is why Apple had (rightfully) decided to
///  mystify those errors a bit. We are still surfacing them cause our users are
///  daredevils.
///
+ (NSError*)betterErrorWithError:(NSError*)error action:(NSString*)action url:(NSURL*)url
{
    NSLog(@"original domain: %@", error.domain);
    NSLog(@"original description: %@", error.localizedDescription);
    NSLog(@"original reason: %@", error.localizedFailureReason);
    NSLog(@"original recovery: %@", error.localizedRecoverySuggestion);
    NSLog(@"original userInfo: %@", error.userInfo);

    // These error messages are not meant for end-users but more for developers as
    // they should only ever occur during development of a product and not when
    // end-users run expected operations. When they occur, a bug in the
    // application is very likely.
    //
    // Any match with these error codes should be logged as a bug in the
    // application.
    //
    NSDictionary* stringMap = @{
        // AudioToolbox/AudioFile.h
        @(kAudioFileUnspecifiedError) : @"an unspecified error has occurred",
        @(kAudioFileUnsupportedFileTypeError) : @"the file type is not supported",
        @(kAudioFileUnsupportedDataFormatError) : @"the data format is not supported by this file type",
        @(kAudioFileUnsupportedPropertyError) : @"the property is not supported",
        @(kAudioFileBadPropertySizeError) : @"the size of the property data was not correct",
        @(kAudioFilePermissionsError) : @"the operation violated the file permissions",
        @(kAudioFileNotOptimizedError) : @"the file must be optimized in order to write more audio data",
        @(kAudioFileInvalidChunkError) : @"the chunk does not exist in the file or is not supported by the file",
        @(kAudioFileDoesNotAllow64BitDataSizeError) : @"the a file offset was too large for the file type",
        @(kAudioFileInvalidPacketOffsetError) : @"a packet offset was past the end of the file, or not at the end of "
                                                @"the file when writing a VBR format, or a corrupt packet size was "
                                                @"read when building the packet table",
        @(kAudioFileInvalidPacketDependencyError) : @"either the packet dependency info that's necessary for the audio "
                                                    @"format has not been provided, or the provided packet dependency info "
                                                    @"indicates dependency on a packet that's unavailable",
        @(kAudioFileInvalidFileError) : @"The file is malformed, or otherwise not a valid instance of an audio "
                                        @"file of its type",
        @(kAudioFileOperationNotSupportedError) : @"the operation cannot be performed",
        @(kAudioFileNotOpenError) : @"the file is closed",
        @(kAudioFileEndOfFileError) : @"end of file",
        @(kAudioFilePositionError) : @"invalid file position",
        @(kAudioFileFileNotFoundError) : @"file not found",
        // AudioToolbox/AUComponent.h
        @(kAudioUnitErr_InvalidProperty) : @"invalid property",
        @(kAudioUnitErr_InvalidParameter) : @"invalid parameter",
        @(kAudioUnitErr_InvalidElement) : @"invalid element",
        @(kAudioUnitErr_NoConnection) : @"no connection",
        @(kAudioUnitErr_FailedInitialization) : @"failed initialization",
        @(kAudioUnitErr_TooManyFramesToProcess) : @"too many frames to process",
        @(kAudioUnitErr_InvalidFile) : @"invalid file",
        @(kAudioUnitErr_UnknownFileType) : @"unknown file type",
        @(kAudioUnitErr_FileNotSpecified) : @"file not specified",
        @(kAudioUnitErr_FormatNotSupported) : @"format not supported",
        @(kAudioUnitErr_Uninitialized) : @"uninitialized",
        @(kAudioUnitErr_InvalidScope) : @"invalid scope",
        @(kAudioUnitErr_PropertyNotWritable) : @"property not writeable",
        @(kAudioUnitErr_CannotDoInCurrentContext) : @"cannot do in current context",
        @(kAudioUnitErr_InvalidPropertyValue) : @"invalid property value",
        @(kAudioUnitErr_PropertyNotInUse) : @"property not in use",
        @(kAudioUnitErr_Initialized) : @"initialized",
        @(kAudioUnitErr_InvalidOfflineRender) : @"invalid offline render",
        @(kAudioUnitErr_Unauthorized) : @"unauthorized",
        @(kAudioUnitErr_MIDIOutputBufferFull) : @"MIDI output buffer full",
        @(kAudioComponentErr_InstanceTimedOut) : @"instance timeout",
        @(kAudioComponentErr_InstanceInvalidated) : @"instance invalidated",
        @(kAudioUnitErr_RenderTimeout) : @"render timeout",
        @(kAudioUnitErr_ExtensionNotFound) : @"extension not found",
        @(kAudioUnitErr_InvalidParameterValue) : @"invalid parameter value",
        @(kAudioUnitErr_InvalidFilePath) : @"invalid file path",
        @(kAudioUnitErr_MissingKey) : @"missing key",
        @(kAudioUnitErr_ComponentManagerNotSupported) : @"content manager not supported",
        // AudioToolbox/ExtendedAudioFile.h
        @(kExtAudioFileError_InvalidProperty) : @"invalid property",
        @(kExtAudioFileError_InvalidPropertySize) : @"invalid property size",
        @(kExtAudioFileError_NonPCMClientFormat) : @"not a PCM client format",
        @(kExtAudioFileError_InvalidChannelMap) : @"number of channels doesn't match format",
        @(kExtAudioFileError_InvalidOperationOrder) : @"invalid order of operations",
        @(kExtAudioFileError_InvalidDataFormat) : @"invalid date format",
        @(kExtAudioFileError_MaxPacketSizeUnknown) : @"maximum packet size is unknown",
        @(kExtAudioFileError_InvalidSeek) : @"writing, or offset out of bounds",
        @(kExtAudioFileError_AsyncWriteTooLarge) : @"async write too large",
        @(kExtAudioFileError_AsyncWriteBufferOverflow) : @"an async write could not be completed in time",
        // CoreMIDI/MIDIServices.h
        @(kMIDIInvalidClient) : @"an invalid MIDIClientRef was passed",
        @(kMIDIInvalidPort) : @"an invalid MIDIPortRef was passed",
        @(kMIDIWrongEndpointType) : @"a source endpoint was passed to a function "
                                    @"expecting a destination, or vice versa",
        @(kMIDINoConnection) : @"attempt to close a non-existant connection",
        @(kMIDIUnknownEndpoint) : @"an invalid MIDIEndpointRef was passed",
        @(kMIDIUnknownProperty) : @"attempt to query a property not set on the object",
        @(kMIDIWrongPropertyType) : @"attempt to set a property with a value not of the correct type",
        @(kMIDINoCurrentSetup) : @"internal error; there is no current MIDI setup object",
        @(kMIDIMessageSendErr) : @"communication with MIDIServer failed",
        @(kMIDIServerStartErr) : @"unable to start MIDIServer",
        @(kMIDISetupFormatErr) : @"unable to read the saved state",
        @(kMIDIWrongThread) : @"a driver is calling a non-I/O function in the server from a thread "
                              @"other than the server's main thread",
        @(kMIDIObjectNotFound) : @"the requested object does not exist",
        @(kMIDIIDNotUnique) : @"attempt to set a non-unique kMIDIPropertyUniqueID on an object",
        @(kMIDINotPermitted) : @"the process does not have privileges for the requested operation",
        @(kMIDIUnknownError) : @"internal error; unable to perform the requested operation",
    };

    NSString* description = error.localizedDescription;
    NSString* failureReason = error.localizedFailureReason;
    NSString* fileName = [[url filePathURL] lastPathComponent];

    // Remove the possible framework error code postfix from the description.
    // Example "(com.apple.avfaudio error XXXXXXXX)".
    NSString* frameworkErrorCodePrefix = [NSString stringWithFormat:@"(%@ error ", error.domain];
    NSRange range = [description rangeOfString:frameworkErrorCodePrefix];
    if (range.length > 0) {
        description = [description substringToIndex:range.location];
    }

    if (failureReason == nil) {
        // Reduce the hard to read fully qualified framework name into the last
        // component.
        NSArray<NSString*>* frameworkComponents = [error.domain componentsSeparatedByString:@"."];
        NSString* frameworkName = frameworkComponents[frameworkComponents.count - 1];

        // Set a default action.
        if (action == nil) {
            action = @"process";
        }

        // Make sure the file we were trying to access is mentioned in the error
        // messages.
        NSString* urlInsert = @"";
        if (fileName != nil && ![description containsString:fileName]) {
            urlInsert = [NSString stringWithFormat:@" \"%@\"", fileName];
        }

        // Add the trigraph from the error code (OSStatus) if available.
        NSString* trigraphInsert = @"";
        NSString* trigraph = [NSError stringFromOSStatus:error.code];
        if (trigraph != nil) {
            trigraphInsert = [NSString stringWithFormat:@" (%@)", trigraph];
        }

        // Try to add description derived from the hopefully not known error code.
        NSString* debugMessage = stringMap[@(error.code)];
        NSString* developerDescriptionInsert = @" returned an error";
        if (debugMessage != nil) {
            // This is very likely an application bug and not a user error.
            developerDescriptionInsert = [NSString stringWithFormat:@" returned: %@", debugMessage];
        }

        // Example output:
        // When trying to process "foobar.mp3" avfaudio returned: the file type is
        // not supported (typ?).
        failureReason =
            [NSString stringWithFormat:@"When trying to %@%@ %@ %@%@.", action, urlInsert, frameworkName, developerDescriptionInsert, trigraphInsert];
    }

    NSDictionary* userInfo = @{
        NSLocalizedDescriptionKey : description,
        NSLocalizedFailureReasonErrorKey : failureReason,
    };

    return [NSError errorWithDomain:[[NSBundle bundleForClass:[self class]] bundleIdentifier] code:error.code userInfo:userInfo];
}

@end
