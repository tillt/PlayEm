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
    NSString *bad = @"Fran\u00e7ois becomes FranÃ§ois and EspaÃ±a and piÃ±a colada";
    NSString *san = [bad sanitizedMetadataString];
    NSString *expected = @"François becomes François and España and piña colada";
    XCTAssertEqualObjects(san, expected, @"sanitized string mismatch: %@", san);
    XCTAssertFalse([san containsString:@"Ã"], @"still contains marker in %@", san);
    XCTAssertFalse([san containsString:@"Ã±"], @"still contains marker in %@", san);
    XCTAssertFalse([san containsString:@"Ã§"], @"still contains marker in %@", san);
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

- (void)testSanitizesShazamMojibake
{
    const uint8_t badBytes[] = {
        0x54,0x6F,0x77,0x6E,0x20,0x4A,0x6F,0x6B,0x65,0x72,0x20,0x28,0x50,0x68,0x69,0x6C,0x69,0x70,0x20,0x42,0x61,0x64,0x65,0x72,0x20,0x26,0x20,0x4E,0x69,0x63,0x6F,0x6E,0xC3,0xA2,0xC2,0x88,0xC2,0x9A,0xC3,0x82,0xC2,0xAE,0x20,0x52,0x65,0x6D,0x69,0x78,0x29
    };
    NSData *badData = [NSData dataWithBytes:badBytes length:sizeof(badBytes)];
    NSString *bad = [[NSString alloc] initWithData:badData encoding:NSUTF8StringEncoding];
    NSString *san = [bad sanitizedMetadataString];
    const uint8_t expectedBytes[] = {
        0x54,0x6F,0x77,0x6E,0x20,0x4A,0x6F,0x6B,0x65,0x72,0x20,0x28,0x50,0x68,0x69,0x6C,0x69,0x70,0x20,0x42,0x61,0x64,0x65,0x72,0x20,0x26,0x20,0x4E,0x69,0x63,0x6F,0x6E,0xC3,0xA8,0x20,0x52,0x65,0x6D,0x69,0x78,0x29
    };
    NSString *expected = [[NSString alloc] initWithBytes:expectedBytes length:sizeof(expectedBytes) encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(san, expected);
    XCTAssertFalse([san containsString:@"â"], @"still contains marker in %@", san);
    XCTAssertFalse([san containsString:@"Â"], @"still contains marker in %@", san);
    XCTAssertFalse([san containsString:@"Ã"], @"still contains marker in %@", san);
}

- (void)testBulkSamplesFromLog
{
    // Build the special Town Joker sample from bytes to avoid control chars in source.
    const uint8_t townBadBytes[] = {
        0x54,0x6F,0x77,0x6E,0x20,0x4A,0x6F,0x6B,0x65,0x72,0x20,0x28,0x50,0x68,0x69,0x6C,0x69,0x70,0x20,0x42,0x61,0x64,0x65,0x72,0x20,0x26,0x20,0x4E,0x69,0x63,0x6F,0x6E,0xC3,0xA2,0xC2,0x88,0xC2,0x9A,0xC3,0x82,0xC2,0xAE,0x20,0x52,0x65,0x6D,0x69,0x78,0x29
    };
    NSString *townBad = [[NSString alloc] initWithBytes:townBadBytes length:sizeof(townBadBytes) encoding:NSUTF8StringEncoding];
    const uint8_t townExpectedBytes[] = {
        0x54,0x6F,0x77,0x6E,0x20,0x4A,0x6F,0x6B,0x65,0x72,0x20,0x28,0x50,0x68,0x69,0x6C,0x69,0x70,0x20,0x42,0x61,0x64,0x65,0x72,0x20,0x26,0x20,0x4E,0x69,0x63,0x6F,0x6E,0xC3,0xA8,0x20,0x52,0x65,0x6D,0x69,0x78,0x29
    };
    NSString *townExpected = [[NSString alloc] initWithBytes:townExpectedBytes length:sizeof(townExpectedBytes) encoding:NSUTF8StringEncoding];

    NSArray<NSDictionary<NSString*, NSString*>*> *samples = @[
        // Clean control
        @{ @"input": @"Have No Fear (Edit)", @"expected": @"Have No Fear (Edit)" },
        // Mojibake cases we actually care about.
        @{ @"input": @"FranÃ§ois becomes FranÃ§ois and EspaÃ±a and piÃ±a colada",
            @"expected": @"François becomes François and España and piña colada" },
        @{ @"input": townBad, @"expected": townExpected },
    ];

    for (NSDictionary<NSString*, NSString*> *sample in samples) {
        NSString *input = sample[@"input"];
        NSString *expected = sample[@"expected"];
        NSString *san = [input sanitizedMetadataString];
        XCTAssertEqualObjects(san, expected, @"Mismatch for input %@", input);
    }
}

- (void)testNonLatinPassThrough
{
    NSArray<NSString*> *inputs = @[
        @"你好，世界",           // Chinese
        @"Привет, мир",         // Cyrillic
        @"こんにちは世界",      // Japanese
        @"안녕하세요 세계",        // Korean
        @"nuqneH tlhIngan",     // Klingon (Latin letters)
    ];
    for (NSString *input in inputs) {
        NSString *san = [input sanitizedMetadataString];
        XCTAssertEqualObjects(san, input);
    }
}

@end
