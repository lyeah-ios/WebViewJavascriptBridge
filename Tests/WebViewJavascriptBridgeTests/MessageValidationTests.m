#import <XCTest/XCTest.h>
#import "WebViewJavascriptBridgeBase.h"
#import <objc/runtime.h>

@interface WebViewJavascriptBridgeBase (LoggingTests)
+ (void)wvjb_log:(NSString *)action message:(id)message debug:(BOOL)debug;
@end

static IMP originalLogImplementation;
static NSString * const logEventsKey = @"MessageValidationTests.logEvents";

static void captureLogEvent(id receiver, SEL selector, NSString *action, id message, BOOL debug) {
    NSMutableArray *events = [NSThread currentThread].threadDictionary[logEventsKey];
    if (events && !debug) {
        [events addObject:@[action ?: [NSNull null], message ?: [NSNull null]]];
    } else {
        ((void (*)(id, SEL, NSString *, id, BOOL))originalLogImplementation)(receiver, selector, action, message, debug);
    }
}

@interface LoggingTestDelegate : NSObject <WebViewJavascriptBridgeBaseDelegate>
@property (nonatomic) BOOL authorize;
@end

@implementation LoggingTestDelegate
- (BOOL)wvjb_authorizeContext:(WVJBMessageContext *)context handlerName:(NSString *)handlerName {
    return self.authorize;
}
- (void)wvjb_evaluateJavascript:(NSString *)javascriptCommand inFrame:(WKFrameInfo *)frame completionHandler:(void (^)(id, NSError *))completionHandler {
    if (completionHandler) completionHandler(nil, [NSError errorWithDomain:@"secret-error-domain" code:73 userInfo:@{NSLocalizedDescriptionKey: @"secret-error-description"}]);
}
@end

@interface FrameInfoReceiver : NSObject <WKScriptMessageHandler>
@property (nonatomic, strong) WKFrameInfo *frameInfo;
@property (nonatomic, strong) XCTestExpectation *expectation;
@end

@implementation FrameInfoReceiver
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
    self.frameInfo = message.frameInfo;
    [self.expectation fulfill];
}
@end

@interface XCTestCase (FrameInfoTesting) <WebViewJavascriptBridgeBaseDelegate>
- (WKFrameInfo *)testMainFrameInfo;
@end

@implementation XCTestCase (FrameInfoTesting)
- (BOOL)wvjb_authorizeContext:(WVJBMessageContext *)context handlerName:(NSString *)handlerName {
    return YES;
}
- (void)wvjb_evaluateJavascript:(NSString *)javascriptCommand inFrame:(WKFrameInfo *)frame completionHandler:(void (^)(id, NSError *))completionHandler {
    if (completionHandler) completionHandler(nil, nil);
}
- (WKFrameInfo *)testMainFrameInfo {
    FrameInfoReceiver *receiver = [FrameInfoReceiver new];
    receiver.expectation = [[XCTestExpectation alloc] initWithDescription:@"Receive real main frame info"];
    WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
    [configuration.userContentController addScriptMessageHandler:receiver name:@"frameInfo"];
    WKWebView *webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
    [webView loadHTMLString:@"<script>window.webkit.messageHandlers.frameInfo.postMessage('ready');</script>" baseURL:nil];
    XCTWaiterResult result = [XCTWaiter waitForExpectations:@[receiver.expectation] timeout:5];
    XCTAssertEqual(result, XCTWaiterResultCompleted);
    XCTAssertNotNil(receiver.frameInfo);
    XCTAssertTrue(receiver.frameInfo.isMainFrame);
    [configuration.userContentController removeScriptMessageHandlerForName:@"frameInfo"];
    return receiver.frameInfo;
}
@end

@interface MessageValidationTests : XCTestCase
@end

@implementation MessageValidationTests

- (void)testErrorEventsDoNotContainSensitivePayloads
{
    WKFrameInfo *frame = [self testMainFrameInfo];
    if (!frame) return;
    WebViewJavascriptBridgeBase *bridge = [WebViewJavascriptBridgeBase new];
    LoggingTestDelegate *delegate = [LoggingTestDelegate new];
    delegate.authorize = YES;
    bridge.delegate = delegate;
    NSMutableArray *events = [NSMutableArray array];
    Method method = class_getClassMethod([WebViewJavascriptBridgeBase class], @selector(wvjb_log:message:debug:));
    XCTAssertNotEqual(method, NULL);
    if (!method) return;

    @synchronized ([WebViewJavascriptBridgeBase class]) {
        originalLogImplementation = method_getImplementation(method);
        [NSThread currentThread].threadDictionary[logEventsKey] = events;
        @try {
            method_setImplementation(method, (IMP)captureLogEvent);
            WKFrameInfo * _Nullable missingFrame = nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullable-to-nonnull-conversion"
            [bridge handleMessage:@{ @"data": @"secret-no-frame" } frameInfo:missingFrame];
#pragma clang diagnostic pop
            [bridge handleMessage:@"{\"data\":\"secret-invalid-json\"" frameInfo:frame];
            [bridge handleMessage:@{ @"__wvjbReady": @"secret-ready" } frameInfo:frame];
            [bridge handleMessage:@{ @"handlerName": @[@"secret-field"], @"data": @"secret-field-data" } frameInfo:frame];
            [bridge handleMessage:@{ @"data": @"secret-missing-handler" } frameInfo:frame];
            [bridge handleMessage:@{ @"handlerName": @"secret-unknown-handler", @"data": @"secret-handler-data" } frameInfo:frame];
            [bridge handleMessage:@{ @"responseId": @"secret-callback-id", @"responseData": @"secret-response-data" } frameInfo:frame];
            delegate.authorize = NO;
            [bridge handleMessage:@{ @"handlerName": @"secret-denied-handler", @"data": @"secret-denied-data" } frameInfo:frame];
            [bridge bridgeDidBecomeReady];
            [bridge sendData:@"secret-outgoing-data" responseCallback:nil handlerName:@"secret-outgoing-handler"];
        } @finally {
            method_setImplementation(method, originalLogImplementation);
            [[NSThread currentThread].threadDictionary removeObjectForKey:logEventsKey];
        }
    }
    XCTAssertEqualObjects(events, (@[
        @[@"WARNING", @"Rejected message without frame information"],
        @[@"WARNING", @"Invalid message received"],
        @[@"WARNING", @"Invalid ready flag"],
        @[@"WARNING", @"Invalid message field: handlerName"],
        @[@"WARNING", @"Missing handler name"],
        @[@"WARNING", @"No handler for message from JavaScript"],
        @[@"WARNING", @"Received response for unknown callback"],
        @[@"WARNING", @"Rejected unauthorized handler"],
        @[@"ERROR", @"JavaScript evaluation failed (code 73)"]
    ]));
}

- (void)testMalformedMessagesAreIgnored
{
    WebViewJavascriptBridgeBase *bridge = [WebViewJavascriptBridgeBase new];
    bridge.delegate = self;
    WKFrameInfo *frame = [self testMainFrameInfo];
    __block NSUInteger calls = 0;
    bridge.messageHandlers[@"test"] = ^(WVJBMessageContext *context) { calls++; };
    NSArray *messages = @[
        @[], @42, @"null", @"{", @{},
        @{ @"__wvjbReady": @[] }, @{ @"__wvjbReady": @"YES" },
        @{ @"handlerName": @[] }, @{ @"handlerName": [NSNull null] },
        @{ @"handlerName": @"test", @"callbackId": @{} },
        @{ @"responseId": @[] }, @{ @"responseId": [NSNull null] },
        @{ @"handlerName": @"test", @"responseId": @42 }
    ];
    for (id message in messages) {
        XCTAssertNoThrow([bridge handleMessage:message frameInfo:frame]);
    }
    XCTAssertEqual(calls, 0u);
    XCTAssertNotNil(bridge.startupMessageQueue);
}

- (void)testValidMessagesAndResponses
{
    WebViewJavascriptBridgeBase *bridge = [WebViewJavascriptBridgeBase new];
    bridge.delegate = self;
    WKFrameInfo *frame = [self testMainFrameInfo];
    __block id received = nil;
    bridge.messageHandlers[@"test"] = ^(WVJBMessageContext *context) { received = context.data; };
    [bridge handleMessage:@"{\"handlerName\":\"test\",\"data\":42,\"callbackId\":\"cb_1\"}" frameInfo:frame];
    XCTAssertEqualObjects(received, @42);

    __block id response = nil;
    bridge.responseCallbacks[@"response"] = [^(id data) { response = data; } copy];
    [bridge handleMessage:@{ @"responseId": @"response", @"responseData": @"ok" } frameInfo:frame];
    XCTAssertEqualObjects(response, @"ok");
    XCTAssertNil(bridge.responseCallbacks[@"response"]);
    [bridge handleMessage:@{ @"__wvjbReady": @YES } frameInfo:frame];
    XCTAssertNil(bridge.startupMessageQueue);
}

- (void)testMalformedMessagesDoNotInterruptValidMessagesOrConsumeCallbacks
{
    WebViewJavascriptBridgeBase *bridge = [WebViewJavascriptBridgeBase new];
    bridge.delegate = self;
    WKFrameInfo *frame = [self testMainFrameInfo];
    NSMutableArray *received = [NSMutableArray array];
    bridge.messageHandlers[@"test"] = ^(WVJBMessageContext *context) { [received addObject:context.data]; };
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
        XCTAssertNoThrow([bridge handleMessage:message frameInfo:frame]);
    }
    XCTAssertEqualObjects(received, (@[@"before", @"after"]));
    XCTAssertEqual(responses, 0u);
    XCTAssertNotNil(bridge.responseCallbacks[@"pending"]);
    XCTAssertNotNil(bridge.startupMessageQueue);
    [bridge handleMessage:@{ @"responseId": @"pending", @"responseData": @"response" } frameInfo:frame];
    XCTAssertEqual(responses, 1u);
    XCTAssertNil(bridge.responseCallbacks[@"pending"]);
}

- (void)testContextCallbackPresenceAndRelease
{
    WebViewJavascriptBridgeBase *bridge = [WebViewJavascriptBridgeBase new];
    bridge.delegate = self;
    WKFrameInfo *frame = [self testMainFrameInfo];
    __block NSUInteger calls = 0;
    __block __weak WVJBMessageContext *weakContext = nil;
    __block WVJBResponseCallback savedCallback = nil;
    bridge.messageHandlers[@"test"] = ^(WVJBMessageContext *context) {
        calls++;
        XCTAssertEqual(context.frameInfo, frame);
        if (calls == 1) {
            XCTAssertNil(context.responseCallback);
        } else {
            XCTAssertNotNil(context.responseCallback);
            weakContext = context;
            savedCallback = context.responseCallback;
        }
    };
    @autoreleasepool {
        [bridge handleMessage:@{ @"handlerName": @"test" } frameInfo:frame];
        [bridge handleMessage:@{ @"handlerName": @"test", @"callbackId": @"cb_1" } frameInfo:frame];
    }
    XCTAssertEqual(calls, 2u);
    XCTAssertNotNil(savedCallback);
    XCTAssertNil(weakContext);
    if (savedCallback) savedCallback(@"reply");
}

@end
