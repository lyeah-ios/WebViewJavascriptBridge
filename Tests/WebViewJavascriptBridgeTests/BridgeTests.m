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
@property (nonatomic, copy) void (^onFinish)(WKWebView *webView);
@end

@implementation BridgeTests {
    WKWebView *_wkWebView;
    NSMutableArray* _retains;
    NSMapTable<WKWebView *, WebViewJavascriptBridge *> *_bridges;
}

- (void)setUp {
    [super setUp];
    
    UIViewController *rootVC = [[(AppDelegate *)[[UIApplication sharedApplication] delegate] window] rootViewController];
    CGRect frame = rootVC.view.bounds;
    frame.size.height /= 2;
    frame.origin.y += frame.size.height;
    _retains = [NSMutableArray array];
    _bridges = [NSMapTable strongToStrongObjectsMapTable];
    WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
    [configuration.userContentController addUserScript:[WebViewJavascriptBridge userScript]];
    _wkWebView = [[WKWebView alloc] initWithFrame:frame configuration:configuration];
    WebViewJavascriptBridge *bridge = [WebViewJavascriptBridge bridgeForWebView:_wkWebView];
    [_bridges setObject:bridge forKey:_wkWebView];
    _wkWebView.backgroundColor = [UIColor redColor];
    [rootVC.view addSubview:_wkWebView];
    
}

- (void)tearDown {
    [super tearDown];
    [_wkWebView removeFromSuperview];
}

- (WebViewJavascriptBridge*)bridgeForWebView:(id)webView {
    WebViewJavascriptBridge* bridge = [_bridges objectForKey:webView];
    XCTAssertNotNil(bridge);
    return bridge;
}

- (WKWebView *)configuredWebView {
    WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
    [configuration.userContentController addUserScript:[WebViewJavascriptBridge userScript]];
    WKWebView *webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
    WebViewJavascriptBridge *bridge = [WebViewJavascriptBridge bridgeForWebView:webView];
    [_bridges setObject:bridge forKey:webView];
    [_retains addObject:webView];
    return webView;
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
    TestWebPageLoadDelegate *delegate = [TestWebPageLoadDelegate new];
    [_retains addObject:delegate];
    delegate.onFinish = ^(WKWebView *loadedWebView) {
        [bridge callHandler:echoHandler data:@"testEchoHandler" responseCallback:^(id responseData) {
            XCTAssertEqualObjects(responseData, @"testEchoHandler");
            [callbackInvocked fulfill];
        }];
    };
    ((WKWebView *)webView).navigationDelegate = delegate;
    loadEchoSample(webView);
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
    [self bridgeForWebView:webView];
    TestWebPageLoadDelegate* delegate = [TestWebPageLoadDelegate new];
    delegate.expectation = [self expectationWithDescription:@"Webpage loaded"];
    delegate.policyExpectation = [self expectationWithDescription:@"Navigation policy forwarded"];
    [_retains addObject:delegate];
    ((WKWebView *)webView).navigationDelegate = delegate;
    XCTAssertEqual(((WKWebView *)webView).navigationDelegate, delegate);
    loadEchoSample(webView);
}

- (void)testUnconfiguredWebViewFails {
    WKWebView *webView = [[WKWebView alloc] initWithFrame:CGRectZero];
    XCTAssertNil([WebViewJavascriptBridge bridgeForWebView:webView]);
}

- (void)testUserScriptFrameScopes {
    WKUserScript *defaultScript = [WebViewJavascriptBridge userScript];
    WKUserScript *mainFrameScript = [WebViewJavascriptBridge userScriptForMainFrameOnly:YES];
    WKUserScript *allFramesScript = [WebViewJavascriptBridge userScriptForMainFrameOnly:NO];
    XCTAssertTrue(defaultScript.isForMainFrameOnly);
    XCTAssertTrue(mainFrameScript.isForMainFrameOnly);
    XCTAssertFalse(allFramesScript.isForMainFrameOnly);
    for (WKUserScript *script in @[defaultScript, mainFrameScript, allFramesScript]) {
        XCTAssertEqual(script.injectionTime, WKUserScriptInjectionTimeAtDocumentStart);
        XCTAssertEqualObjects(script.source, defaultScript.source);
        WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
        [configuration.userContentController addUserScript:script];
        WKWebView *webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
        WebViewJavascriptBridge *bridge = [WebViewJavascriptBridge bridgeForWebView:webView];
        XCTAssertNotNil(bridge);
    }
}

- (void)testSubframeReadyPreservesMainFrameCallbackAndDeliversMessage {
    WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
    [configuration.userContentController addUserScript:[WebViewJavascriptBridge userScriptForMainFrameOnly:NO]];
    WKWebView *webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
    WebViewJavascriptBridge *bridge = [WebViewJavascriptBridge bridgeForWebView:webView];
    XCTAssertNotNil(bridge);
    [_retains addObjectsFromArray:@[webView, bridge]];

    XCTestExpectation *subframeMessage = [self expectationWithDescription:@"Subframe message delivered"];
    XCTestExpectation *mainResponse = [self expectationWithDescription:@"Main frame pending callback delivered"];
    [bridge registerHandler:@"mainHandlerStarted" handler:^(id data, WVJBResponseCallback callback) {
        NSString *javascript = @"var frame = document.createElement('iframe'); frame.srcdoc = '<script>document.addEventListener(\"DOMContentLoaded\", function() { WebViewJavascriptBridge.callHandler(\"subframeMessage\", \"from iframe\"); });</script>'; document.body.appendChild(frame); true;";
        [webView evaluateJavaScript:javascript completionHandler:^(id result, NSError *error) {
            XCTAssertNil(error);
        }];
    }];
    [bridge registerHandler:@"subframeMessage" handler:^(id data, WVJBResponseCallback callback) {
        XCTAssertEqualObjects(data, @"from iframe");
        [subframeMessage fulfill];
        [webView evaluateJavaScript:@"window.pendingResponse('main response')" completionHandler:^(id result, NSError *error) {
            XCTAssertNil(error);
        }];
    }];

    TestWebPageLoadDelegate *delegate = [TestWebPageLoadDelegate new];
    [_retains addObject:delegate];
    webView.navigationDelegate = delegate;
    delegate.onFinish = ^(WKWebView *loadedWebView) {
        [bridge callHandler:@"holdResponse" data:nil responseCallback:^(id response) {
            XCTAssertEqualObjects(response, @"main response");
            [mainResponse fulfill];
        }];
    };
    [webView loadHTMLString:@"<html><body><script>WebViewJavascriptBridge.registerHandler('holdResponse', function(data, callback) { window.pendingResponse = callback; WebViewJavascriptBridge.callHandler('mainHandlerStarted'); });</script></body></html>" baseURL:nil];
    [self waitForExpectationsWithTimeout:timeoutSec handler:NULL];
}

- (void)testBridgeRejectsNonMatchingScripts {
    NSString *source = [WebViewJavascriptBridge userScript].source;
    NSArray<WKUserScript *> *scripts = @[
        [[WKUserScript alloc] initWithSource:source injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:NO],
        [[WKUserScript alloc] initWithSource:@"different script" injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO]
    ];
    for (WKUserScript *script in scripts) {
        WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
        [configuration.userContentController addUserScript:script];
        WKWebView *webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
        XCTAssertNil([WebViewJavascriptBridge bridgeForWebView:webView]);
    }
}

- (void)testResponseCallbackIsRemovedAfterDelivery {
    WebViewJavascriptBridgeBase *base = [WebViewJavascriptBridgeBase new];
    __block id received = nil;
    [base sendData:nil responseCallback:^(id data) { received = data; } handlerName:@"test"];
    NSString *callbackID = [base.responseCallbacks.allKeys firstObject];
    XCTAssertNotNil(callbackID);
    [base handleMessage:@{ @"responseId": callbackID, @"responseData": @"ok" }];
    XCTAssertEqualObjects(received, @"ok");
    XCTAssertEqual(base.responseCallbacks.count, 0u);
}

- (void)testUnknownResponseDoesNotCrash {
    WebViewJavascriptBridgeBase *base = [WebViewJavascriptBridgeBase new];
    NSDictionary *message = @{ @"responseId": @"missing", @"responseData": @"ignored" };
    XCTAssertNoThrow([base handleMessage:message]);
}

- (void)testJSONStringMessageBody {
    WebViewJavascriptBridgeBase *base = [WebViewJavascriptBridgeBase new];
    __block id received = nil;
    base.messageHandlers[@"stringMessage"] = ^(id data, WVJBResponseCallback callback) {
        received = data;
    };
    [base handleMessage:@"{\"handlerName\":\"stringMessage\",\"data\":\"hello\"}"];
    XCTAssertEqualObjects(received, @"hello");
}

- (void)testConfiguredWebViewSupportsLegacyH5Initialization {
    WKWebView *webView = [self configuredWebView];
    WebViewJavascriptBridge *bridge = [self bridgeForWebView:webView];
    XCTestExpectation *callbackInvoked = [self expectationWithDescription:@"Legacy H5 callback invoked"];

    [bridge callHandler:echoHandler data:@"legacy H5" responseCallback:^(id responseData) {
        XCTAssertEqualObjects(responseData, @"legacy H5");
        [callbackInvoked fulfill];
    }];
    loadEchoSample(webView);

    [self waitForExpectationsWithTimeout:timeoutSec handler:NULL];
}

- (void)testConfiguredWebViewSupportsStringParametersAndJSCallback {
    WKWebView *webView = [self configuredWebView];
    WebViewJavascriptBridge *bridge = [self bridgeForWebView:webView];
    XCTestExpectation *callbackInvoked = [self expectationWithDescription:@"String response callback invoked"];

    [bridge registerHandler:@"objcEcho" handler:^(id data, WVJBResponseCallback responseCallback) {
        XCTAssertEqualObjects(data, @"string parameter");
        responseCallback(data);
    }];
    [bridge registerHandler:@"reportResponse" handler:^(id data, WVJBResponseCallback responseCallback) {
        XCTAssertEqualObjects(data, @"string parameter");
        [callbackInvoked fulfill];
    }];
    TestWebPageLoadDelegate *delegate = [TestWebPageLoadDelegate new];
    [_retains addObject:delegate];
    webView.navigationDelegate = delegate;
    delegate.onFinish = ^(WKWebView *loadedWebView) {
        NSString *javascript = @"window.WebViewJavascriptBridge.callHandler('objcEcho', 'string parameter', function(response) { window.WebViewJavascriptBridge.callHandler('reportResponse', response); });";
        [loadedWebView evaluateJavaScript:javascript completionHandler:^(id result, NSError *error) {
            XCTAssertNil(error);
        }];
    };
    loadEchoSample(webView);

    [self waitForExpectationsWithTimeout:timeoutSec handler:NULL];
}

- (void)testConfiguredWebViewDoesNotReplaceExistingNavigationDelegate {
    WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
    [configuration.userContentController addUserScript:[WebViewJavascriptBridge userScript]];
    WKWebView *webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
    TestWebPageLoadDelegate *delegate = [TestWebPageLoadDelegate new];
    webView.navigationDelegate = delegate;
    [_retains addObject:webView];
    [_retains addObject:delegate];

    WebViewJavascriptBridge *bridge = [WebViewJavascriptBridge bridgeForWebView:webView];
    [_retains addObject:bridge];

    XCTAssertEqual(webView.navigationDelegate, delegate);
}

- (void)testConfiguredWebViewsAreIsolated {
    WKWebViewConfiguration *configurationA = [WKWebViewConfiguration new];
    [configurationA.userContentController addUserScript:[WebViewJavascriptBridge userScript]];
    WKWebViewConfiguration *configurationB = [WKWebViewConfiguration new];
    [configurationB.userContentController addUserScript:[WebViewJavascriptBridge userScript]];
    WKWebView *webViewA = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configurationA];
    WKWebView *webViewB = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configurationB];
    [_retains addObject:webViewA];
    [_retains addObject:webViewB];
    WebViewJavascriptBridge *bridgeA = [WebViewJavascriptBridge bridgeForWebView:webViewA];
    WebViewJavascriptBridge *bridgeB = [WebViewJavascriptBridge bridgeForWebView:webViewB];
    [_retains addObjectsFromArray:@[bridgeA, bridgeB]];
    XCTestExpectation *callbackA = [self expectationWithDescription:@"First web view callback invoked"];
    XCTestExpectation *callbackB = [self expectationWithDescription:@"Second web view callback invoked"];

    [bridgeA registerHandler:@"isolatedHandler" handler:^(id data, WVJBResponseCallback responseCallback) {
        XCTAssertEqualObjects(data, @"A");
        responseCallback(@"response A");
    }];
    [bridgeB registerHandler:@"isolatedHandler" handler:^(id data, WVJBResponseCallback responseCallback) {
        XCTAssertEqualObjects(data, @"B");
        responseCallback(@"response B");
    }];
    [bridgeA registerHandler:@"reportResponse" handler:^(id data, WVJBResponseCallback responseCallback) {
        XCTAssertEqualObjects(data, @"response A");
        [callbackA fulfill];
    }];
    [bridgeB registerHandler:@"reportResponse" handler:^(id data, WVJBResponseCallback responseCallback) {
        XCTAssertEqualObjects(data, @"response B");
        [callbackB fulfill];
    }];
    for (WKWebView *webView in @[webViewA, webViewB]) {
        TestWebPageLoadDelegate *delegate = [TestWebPageLoadDelegate new];
        [_retains addObject:delegate];
        webView.navigationDelegate = delegate;
        NSString *value = webView == webViewA ? @"A" : @"B";
        delegate.onFinish = ^(WKWebView *loadedWebView) {
            NSString *javascript = [NSString stringWithFormat:@"window.WebViewJavascriptBridge.callHandler('isolatedHandler', '%@', function(response) { window.WebViewJavascriptBridge.callHandler('reportResponse', response); });", value];
            [loadedWebView evaluateJavaScript:javascript completionHandler:^(id result, NSError *error) {
                XCTAssertNil(error);
            }];
        };
        loadEchoSample(webView);
    }

    [self waitForExpectationsWithTimeout:timeoutSec handler:NULL];
}

- (void)testWebViewAllowsBridgeAfterRelease {
    WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
    [configuration.userContentController addUserScript:[WebViewJavascriptBridge userScript]];
    WKWebView *webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
    WebViewJavascriptBridge *first = [WebViewJavascriptBridge bridgeForWebView:webView];
    XCTAssertNotNil(first);
    first = nil;
    WebViewJavascriptBridge *second = [WebViewJavascriptBridge bridgeForWebView:webView];
    XCTAssertNotNil(second);
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
    if (self.onFinish) {
        self.onFinish(webView);
    }
}
@end
