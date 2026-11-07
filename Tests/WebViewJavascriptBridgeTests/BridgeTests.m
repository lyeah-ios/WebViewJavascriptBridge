//
//  BridgeTests.m
//  WKWebViewJavascriptBridge
//
//  Created by Pieter De Baets on 18/04/2015.
//  Copyright (c) 2015 marcuswestin. All rights reserved.
//

#import <XCTest/XCTest.h>

#import "WebViewJavascriptBridge.h"
#import "AppDelegate.h"

static NSString *const echoHandler = @"echoHandler";

@interface BridgeTests : XCTestCase
@end
@interface TestWebPageLoadDelegate : NSObject<WKNavigationDelegate>
@property XCTestExpectation* expectation;
@property XCTestExpectation* policyExpectation;
@end

@implementation BridgeTests {
    WKWebView *_wkWebView;
    NSMutableArray* _retains;
}

- (void)setUp {
    [super setUp];
    
    UIViewController *rootVC = [[(AppDelegate *)[[UIApplication sharedApplication] delegate] window] rootViewController];
    CGRect frame = rootVC.view.bounds;
    frame.size.height /= 2;
    frame.origin.y += frame.size.height;
    _wkWebView = [[WKWebView alloc] initWithFrame:frame];
    _wkWebView.backgroundColor = [UIColor redColor];
    [rootVC.view addSubview:_wkWebView];
    
    _retains = [NSMutableArray array];
}

- (void)tearDown {
    [super tearDown];
    [_wkWebView removeFromSuperview];
}

- (WebViewJavascriptBridge*)bridgeForWebView:(id)webView {
    WebViewJavascriptBridge* bridge = [WebViewJavascriptBridge bridgeForWebView:webView];
    [_retains addObject:bridge];
    return bridge;
}

static void loadEchoSample(id webView) {
    NSURLRequest *request = [NSURLRequest requestWithURL:[[NSBundle mainBundle] URLForResource:@"echo" withExtension:@"html"]];
    [(WKWebView*)webView loadRequest:request];
}

const NSTimeInterval timeoutSec = 5;

- (void)testEchoHandler {
    [self classSpecificTestEchoHandler:_wkWebView];
    [self waitForExpectationsWithTimeout:timeoutSec handler:NULL];
}
- (void)classSpecificTestEchoHandler:(id)webView {
    WebViewJavascriptBridge *bridge = [self bridgeForWebView:webView];
    
    XCTestExpectation *callbackInvocked = [self expectationWithDescription:@"Callback invoked"];
    [bridge callHandler:echoHandler data:@"testEchoHandler" responseCallback:^(id responseData) {
        XCTAssertEqualObjects(responseData, @"testEchoHandler");
        [callbackInvocked fulfill];
    }];
    
    loadEchoSample(webView);
}

- (void)testEchoHandlerAfterSetup {
    [self classSpecificTestEchoHandlerAfterSetup:_wkWebView];
    [self waitForExpectationsWithTimeout:timeoutSec handler:NULL];
}
- (void)classSpecificTestEchoHandlerAfterSetup:(id)webView {
    WebViewJavascriptBridge *bridge = [self bridgeForWebView:webView];
    
    XCTestExpectation *callbackInvocked = [self expectationWithDescription:@"Callback invoked"];
    loadEchoSample(webView);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 150 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        [bridge callHandler:echoHandler data:@"testEchoHandler" responseCallback:^(id responseData) {
            XCTAssertEqualObjects(responseData, @"testEchoHandler");
            [callbackInvocked fulfill];
        }];
    });
}

- (void)testObjectEncoding {
    [self classSpecificTestObjectEncoding:_wkWebView];
    [self waitForExpectationsWithTimeout:timeoutSec handler:NULL];
}
- (void)classSpecificTestObjectEncoding:(id)webView {
    WebViewJavascriptBridge *bridge = [self bridgeForWebView:webView];
    
    void (^echoObject)(id) = ^void(id object) {
        XCTestExpectation *callbackInvocked = [self expectationWithDescription:@"Callback invoked"];
        [bridge callHandler:echoHandler data:object responseCallback:^(id responseData) {
            XCTAssertEqualObjects(responseData, object);
            [callbackInvocked fulfill];
        }];
    };
    
    echoObject(@"A string sent over the wire");
    echoObject(@"A string with '\"'/\\");
    echoObject(@[ @1, @2, @3 ]);
    echoObject(@{ @"a" : @1, @"b" : @2 });
    echoObject(@{ @"nested" : @[ @YES, [NSNull null], @"line\n\u2028\u2029" ] });
    
    loadEchoSample(webView);
}

- (void)testJavascriptReceiveResponse {
    [self classSpecificTestJavascriptReceiveResponse:_wkWebView];
    [self waitForExpectationsWithTimeout:timeoutSec handler:NULL];
}
- (void)classSpecificTestJavascriptReceiveResponse:(id)webView {
    WebViewJavascriptBridge *bridge = [self bridgeForWebView:webView];
    loadEchoSample(webView);
    XCTestExpectation *callbackInvocked = [self expectationWithDescription:@"Callback invoked"];
    [bridge registerHandler:@"objcEchoToJs" handler:^(id data, WVJBResponseCallback responseCallback) {
        responseCallback(data);
    }];
    [bridge callHandler:@"jsRcvResponseTest" data:nil responseCallback:^(id responseData) {
        XCTAssertEqualObjects(responseData, @"Response from JS");
        [callbackInvocked fulfill];
    }];
}

- (void)testJavascriptReceiveResponseWithoutSafetyTimeout {
    [self classSpecificTestJavascriptReceiveResponseWithoutSafetyTimeout:_wkWebView];
    [self waitForExpectationsWithTimeout:timeoutSec handler:NULL];
}
- (void)classSpecificTestJavascriptReceiveResponseWithoutSafetyTimeout:(id)webView {
    WebViewJavascriptBridge *bridge = [self bridgeForWebView:webView];
    [bridge disableJavscriptAlertBoxSafetyTimeout];
    loadEchoSample(webView);
    XCTestExpectation *callbackInvocked = [self expectationWithDescription:@"Callback invoked"];
    [bridge registerHandler:@"objcEchoToJs" handler:^(id data, WVJBResponseCallback responseCallback) {
        responseCallback(data);
    }];
    [bridge callHandler:@"jsRcvResponseTest" data:nil responseCallback:^(id responseData) {
        XCTAssertEqualObjects(responseData, @"Response from JS");
        [callbackInvocked fulfill];
    }];
}

- (void)testWebpageLoad {
    [self classSpecificTestWebpageLoad:_wkWebView];
    [self waitForExpectationsWithTimeout:timeoutSec handler:NULL];
}
- (void)classSpecificTestWebpageLoad:(id)webView {
    WebViewJavascriptBridge* bridge = [self bridgeForWebView:webView];
    TestWebPageLoadDelegate* delegate = [TestWebPageLoadDelegate new];
    delegate.expectation = [self expectationWithDescription:@"Webpage loaded"];
    delegate.policyExpectation = [self expectationWithDescription:@"Navigation policy forwarded"];
    [_retains addObject:delegate];
    [bridge setWebViewDelegate:delegate];
    loadEchoSample(webView);
}

- (void)testBridgeURLCompatibility {
    WebViewJavascriptBridgeBase *base = [WebViewJavascriptBridgeBase new];
    for (NSString *scheme in @[ @"https", @"wvjbscheme" ]) {
        NSURL *loaded = [NSURL URLWithString:[NSString stringWithFormat:@"%@://__bridge_loaded__", scheme]];
        NSURL *queue = [NSURL URLWithString:[NSString stringWithFormat:@"%@://__wvjb_queue_message__", scheme]];
        XCTAssertTrue([base isWebViewJavascriptBridgeURL:loaded]);
        XCTAssertTrue([base isBridgeLoadedURL:loaded]);
        XCTAssertTrue([base isWebViewJavascriptBridgeURL:queue]);
        XCTAssertTrue([base isQueueMessageURL:queue]);
    }
    XCTAssertFalse([base isWebViewJavascriptBridgeURL:[NSURL URLWithString:@"https://example.com"]]);
    XCTAssertFalse([base isWebViewJavascriptBridgeURL:[NSURL URLWithString:@"http://__bridge_loaded__"]]);
    XCTAssertFalse([base isWebViewJavascriptBridgeURL:[NSURL URLWithString:@"wvjbscheme://unknown"]]);
}

- (void)testResponseCallbackIsRemovedAfterDelivery {
    WebViewJavascriptBridgeBase *base = [WebViewJavascriptBridgeBase new];
    __block id received = nil;
    [base sendData:nil responseCallback:^(id data) { received = data; } handlerName:@"test"];
    NSString *callbackID = [base.responseCallbacks.allKeys firstObject];
    XCTAssertNotNil(callbackID);
    NSData *json = [NSJSONSerialization dataWithJSONObject:@[ @{ @"responseId": callbackID, @"responseData": @"ok" } ] options:0 error:nil];
    [base flushMessageQueue:[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]];
    XCTAssertEqualObjects(received, @"ok");
    XCTAssertEqual(base.responseCallbacks.count, 0u);
}

- (void)testUnknownResponseDoesNotCrash {
    WebViewJavascriptBridgeBase *base = [WebViewJavascriptBridgeBase new];
    NSData *json = [NSJSONSerialization dataWithJSONObject:@[ @{ @"responseId": @"missing", @"responseData": @"ignored" } ] options:0 error:nil];
    XCTAssertNoThrow([base flushMessageQueue:[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]]);
}
@end

@implementation TestWebPageLoadDelegate
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction preferences:(WKWebpagePreferences *)preferences decisionHandler:(void (^)(WKNavigationActionPolicy, WKWebpagePreferences *))decisionHandler {
    if (navigationAction.targetFrame.isMainFrame && navigationAction.request.URL.isFileURL) {
        [self.policyExpectation fulfill];
    }
    decisionHandler(WKNavigationActionPolicyAllow, preferences);
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    [self.expectation fulfill];
}
@end
