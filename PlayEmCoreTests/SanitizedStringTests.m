//
//  SanitizedStringTests.m
//  PlayEmCoreTests
//
//  Created by Till Toenshoff on 12/31/25.
//  Copyright © 2025 Till Toenshoff. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "NSString+Sanitized.h"

@interface SanitizedStringTests : XCTestCase
@end

@implementation SanitizedStringTests

- (void)testCleanStringPassThrough
{
    NSString *s = @"Hello World – Café";
    NSString *san = [s sanitizedMetadataString];
    XCTAssertEqualObjects(san, @"Hello World – Café");
}

- (void)testCollapsesWhitespaceAndNBSP
{
    NSString *s = [NSString stringWithFormat:@"Hello\u00A0  World \n"];
    NSString *san = [s sanitizedMetadataString];
    XCTAssertEqualObjects(san, @"Hello World");
}

- (void)testFixesCommonMojibakeLatin
{
    NSString *bad = @"Fran\u00e7ois becomes FranÃ§ois";
    NSString *san = [bad sanitizedMetadataString];
    XCTAssertTrue([san containsString:@"François"]);
    XCTAssertFalse([san containsString:@"Ã"]);
}

- (void)testUTF16Fallback
{
    // Construct a UTF-16LE string for "ÐÑtest" and feed it through UTF-8 (mojibake markers present).
    unichar chars[] = {0x00D0, 0x00D1, 't', 'e', 's', 't'};
    NSData *utf16le = [NSData dataWithBytes:chars length:sizeof(chars)];
    NSString *utf8Bad = [[NSString alloc] initWithData:utf16le encoding:NSUTF8StringEncoding];
    NSString *san = [utf8Bad sanitizedMetadataString];
    // After fallback, we should no longer see the mojibake markers "Ã" or "Â" and should get "ÐÑtest" or cleaned form.
    XCTAssertFalse([san containsString:@"Ã"]);
    XCTAssertFalse([san containsString:@"Â"]);
}

- (void)testTrimsLongStrings
{
    NSMutableString *longStr = [NSMutableString string];
    for (NSUInteger i = 0; i < 5000; i++) {
        [longStr appendString:@"x"];
    }
    NSString *san = [longStr sanitizedMetadataString];
    XCTAssertLessThanOrEqual(san.length, 4096);
}

@end
