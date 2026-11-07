#import <XCTest/XCTest.h>
#import "WebViewJavascriptBridgeBase.h"

@interface MessageValidationTests : XCTestCase
@end

@implementation MessageValidationTests

- (void)testMalformedMessagesAreIgnored
{
    WebViewJavascriptBridgeBase *bridge = [WebViewJavascriptBridgeBase new];
    __block NSUInteger calls = 0;
    bridge.messageHandlers[@"test"] = ^(id data, WVJBResponseCallback callback) { calls++; };
    NSArray *messages = @[
        @[], @42, @"null", @"{", @{},
        @{ @"__wvjbReady": @[] }, @{ @"__wvjbReady": @"YES" },
        @{ @"handlerName": @[] }, @{ @"handlerName": [NSNull null] },
        @{ @"handlerName": @"test", @"callbackId": @{} },
        @{ @"responseId": @[] }, @{ @"responseId": [NSNull null] },
        @{ @"handlerName": @"test", @"responseId": @42 }
    ];
    for (id message in messages) {
        XCTAssertNoThrow([bridge handleMessage:message]);
    }
    XCTAssertEqual(calls, 0u);
    XCTAssertNotNil(bridge.startupMessageQueue);
}

- (void)testValidMessagesAndResponses
{
    WebViewJavascriptBridgeBase *bridge = [WebViewJavascriptBridgeBase new];
    __block id received = nil;
    bridge.messageHandlers[@"test"] = ^(id data, WVJBResponseCallback callback) { received = data; };
    [bridge handleMessage:@"{\"handlerName\":\"test\",\"data\":42,\"callbackId\":\"cb_1\"}"];
    XCTAssertEqualObjects(received, @42);

    __block id response = nil;
    bridge.responseCallbacks[@"response"] = [^(id data) { response = data; } copy];
    [bridge handleMessage:@{ @"responseId": @"response", @"responseData": @"ok" }];
    XCTAssertEqualObjects(response, @"ok");
    XCTAssertNil(bridge.responseCallbacks[@"response"]);
    [bridge handleMessage:@{ @"__wvjbReady": @YES }];
    XCTAssertNil(bridge.startupMessageQueue);
}

- (void)testMalformedMessagesDoNotInterruptValidMessagesOrConsumeCallbacks
{
    WebViewJavascriptBridgeBase *bridge = [WebViewJavascriptBridgeBase new];
    NSMutableArray *received = [NSMutableArray array];
    bridge.messageHandlers[@"test"] = ^(id data, WVJBResponseCallback callback) { [received addObject:data]; };
    __block NSUInteger responses = 0;
    bridge.responseCallbacks[@"pending"] = [^(id data) {
        XCTAssertEqualObjects(data, @"response");
        responses++;
    } copy];

    NSArray *messages = @[
        @{ @"handlerName": @"test", @"data": @"before" },
        @"{", @{ @"__wvjbReady": @1 },
        @{ @"handlerName": @"test", @"callbackId": @42 },
        @{ @"responseId": @"pending", @"handlerName": @[] },
        @{ @"handlerName": @"test", @"data": @"after" }
    ];
    for (id message in messages) {
        XCTAssertNoThrow([bridge handleMessage:message]);
    }
    XCTAssertEqualObjects(received, (@[@"before", @"after"]));
    XCTAssertEqual(responses, 0u);
    XCTAssertNotNil(bridge.responseCallbacks[@"pending"]);
    XCTAssertNotNil(bridge.startupMessageQueue);
    [bridge handleMessage:@{ @"responseId": @"pending", @"responseData": @"response" }];
    XCTAssertEqual(responses, 1u);
    XCTAssertNil(bridge.responseCallbacks[@"pending"]);
}

@end
