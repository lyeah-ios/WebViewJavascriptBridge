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

@interface XCTestCase (FrameInfoTesting) <WebViewJavascriptBridgeBaseDelegate>
- (WKFrameInfo *)testMainFrameInfo;
@end

@interface BridgeTests : XCTestCase
@end
@interface TestWebPageLoadDelegate : NSObject<WKNavigationDelegate>
@property XCTestExpectation* expectation;
@property XCTestExpectation* policyExpectation;
@property (nonatomic, copy) void (^onFinish)(WKWebView *webView);
@end

@interface EvaluationFrameReceiver : NSObject <WKScriptMessageHandler>
@property (nonatomic, copy) void (^onMessage)(WKScriptMessage *message);
@end

@implementation EvaluationFrameReceiver
- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
    self.onMessage(message);
}
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
    [configuration.userContentController addUserScript:[WebViewJavascriptBridge userScriptForMainFrameOnly:YES]];
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
    [configuration.userContentController addUserScript:[WebViewJavascriptBridge userScriptForMainFrameOnly:YES]];
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

- (void)testEvaluateJavascriptInMainFrame {
    id<WebViewJavascriptBridgeBaseDelegate> bridge = (id)[self bridgeForWebView:_wkWebView];
    XCTestExpectation *success = [self expectationWithDescription:@"Main frame evaluation succeeds"];
    XCTestExpectation *failure = [self expectationWithDescription:@"Main frame JavaScript error returned"];
    [bridge wvjb_evaluateJavascript:@"40 + 2" inFrame:nil completionHandler:^(id result, NSError *error) {
        XCTAssertNil(error);
        XCTAssertEqualObjects(result, @42);
        [success fulfill];
    }];
    [bridge wvjb_evaluateJavascript:@"throw new Error('main failure')" inFrame:nil completionHandler:^(id result, NSError *error) {
        XCTAssertNil(result);
        XCTAssertEqualObjects(error.domain, WKErrorDomain);
        XCTAssertEqual(error.code, WKErrorJavaScriptExceptionOccurred);
        [failure fulfill];
    }];
    [self waitForExpectationsWithTimeout:timeoutSec handler:NULL];
}

- (void)testEvaluateJavascriptInSubframe {
    WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
    [configuration.userContentController addUserScript:[WebViewJavascriptBridge userScriptForMainFrameOnly:YES]];
    EvaluationFrameReceiver *receiver = [EvaluationFrameReceiver new];
    [configuration.userContentController addScriptMessageHandler:receiver name:@"evaluationFrame"];
    WKWebView *webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
    id<WebViewJavascriptBridgeBaseDelegate> bridge = (id)[WebViewJavascriptBridge bridgeForWebView:webView];
    XCTAssertNotNil(bridge);
    XCTestExpectation *success = [self expectationWithDescription:@"Subframe evaluation succeeds"];
    XCTestExpectation *failure = [self expectationWithDescription:@"Subframe JavaScript error returned"];
    receiver.onMessage = ^(WKScriptMessage *message) {
        XCTAssertEqual(message.webView, webView);
        XCTAssertFalse(message.frameInfo.isMainFrame);
        [bridge wvjb_evaluateJavascript:@"window.frameValue" inFrame:message.frameInfo completionHandler:^(id result, NSError *error) {
            XCTAssertNil(error);
            XCTAssertEqualObjects(result, @"child");
            [success fulfill];
        }];
        [bridge wvjb_evaluateJavascript:@"throw new Error('child failure')" inFrame:message.frameInfo completionHandler:^(id result, NSError *error) {
            XCTAssertNil(result);
            XCTAssertEqualObjects(error.domain, WKErrorDomain);
            XCTAssertEqual(error.code, WKErrorJavaScriptExceptionOccurred);
            [failure fulfill];
        }];
    };
    [webView loadHTMLString:@"<script>window.frameValue='main';</script><iframe srcdoc=\"<script>window.frameValue='child'; window.webkit.messageHandlers.evaluationFrame.postMessage('ready');</script>\"></iframe>" baseURL:nil];
    [self waitForExpectationsWithTimeout:timeoutSec handler:NULL];
    [configuration.userContentController removeScriptMessageHandlerForName:@"evaluationFrame"];
    receiver.onMessage = nil;
}

- (void)testEvaluateJavascriptAfterWebViewRelease {
    __block id<WebViewJavascriptBridgeBaseDelegate> bridge;
    __weak __block WKWebView *weakWebView;
    @autoreleasepool {
        WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
        [configuration.userContentController addUserScript:[WebViewJavascriptBridge userScriptForMainFrameOnly:YES]];
        WKWebView *webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
        weakWebView = webView;
        bridge = (id)[WebViewJavascriptBridge bridgeForWebView:webView];
        XCTAssertNotNil(bridge);
    }
    NSPredicate *released = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
        return weakWebView == nil;
    }];
    XCTestExpectation *releaseExpectation = [self expectationForPredicate:released evaluatedWithObject:nil handler:nil];
    [self waitForExpectations:@[releaseExpectation] timeout:timeoutSec];
    XCTAssertNil(weakWebView);
    XCTestExpectation *failure = [self expectationWithDescription:@"Released web view returns an error"];
    [bridge wvjb_evaluateJavascript:@"42" inFrame:nil completionHandler:^(id result, NSError *error) {
        XCTAssertNil(result);
        XCTAssertEqualObjects(error.domain, @"WebViewJavascriptBridge");
        XCTAssertEqual(error.code, 1);
        [failure fulfill];
    }];
    [self waitForExpectationsWithTimeout:timeoutSec handler:NULL];
}

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
    [bridge registerHandler:@"objcEchoToJs" handler:^(WVJBMessageContext *context) {
        context.responseCallback(context.data);
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
    [bridge registerHandler:@"objcEchoToJs" handler:^(WVJBMessageContext *context) {
        context.responseCallback(context.data);
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
    WKUserScript *mainFrameScript = [WebViewJavascriptBridge userScriptForMainFrameOnly:YES];
    WKUserScript *allFramesScript = [WebViewJavascriptBridge userScriptForMainFrameOnly:NO];
    XCTAssertTrue(mainFrameScript.isForMainFrameOnly);
    XCTAssertFalse(allFramesScript.isForMainFrameOnly);
    for (WKUserScript *script in @[mainFrameScript, allFramesScript]) {
        XCTAssertEqual(script.injectionTime, WKUserScriptInjectionTimeAtDocumentStart);
        XCTAssertEqualObjects(script.source, mainFrameScript.source);
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
    bridge.authorizationHandler = ^BOOL(WVJBMessageContext *context, NSString *handlerName) {
        return context.frameInfo.isMainFrame || [handlerName isEqualToString:@"subframeMessage"];
    };

    XCTestExpectation *subframeMessage = [self expectationWithDescription:@"Subframe message delivered"];
    XCTestExpectation *mainResponse = [self expectationWithDescription:@"Main frame pending callback delivered"];
    [bridge registerHandler:@"mainHandlerStarted" handler:^(WVJBMessageContext *context) {
        NSString *javascript = @"var frame = document.createElement('iframe'); frame.srcdoc = '<script>document.addEventListener(\"DOMContentLoaded\", function() { WebViewJavascriptBridge.callHandler(\"subframeMessage\", \"from iframe\"); });</script>'; document.body.appendChild(frame); true;";
        [webView evaluateJavaScript:javascript completionHandler:^(id result, NSError *error) {
            XCTAssertNil(error);
        }];
    }];
    [bridge registerHandler:@"subframeMessage" handler:^(WVJBMessageContext *context) {
        XCTAssertEqualObjects(context.data, @"from iframe");
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
    NSString *source = [WebViewJavascriptBridge userScriptForMainFrameOnly:YES].source;
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

- (void)testDefaultAuthorizationRejectsSubframe {
    WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
    [configuration.userContentController addUserScript:[WebViewJavascriptBridge userScriptForMainFrameOnly:NO]];
    WKWebView *webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
    WebViewJavascriptBridge *bridge = [WebViewJavascriptBridge bridgeForWebView:webView];
    [_retains addObjectsFromArray:@[webView, bridge]];
    XCTestExpectation *rejected = [self expectationWithDescription:@"Subframe handler must not run"];
    rejected.inverted = YES;
    XCTestExpectation *main = [self expectationWithDescription:@"Main frame remains authorized"];
    [bridge registerHandler:@"attempt" handler:^(WVJBMessageContext *context) {
        if (context.frameInfo.isMainFrame) {
            XCTAssertEqualObjects(context.data, @"main");
            [main fulfill];
        } else {
            [rejected fulfill];
        }
    }];
    [webView loadHTMLString:@"<html><body><script>WebViewJavascriptBridge.callHandler('attempt','main'); window.addEventListener('message', function() { WebViewJavascriptBridge.callHandler('attempt','main'); }, {once:true});</script><iframe srcdoc=\"<script>WebViewJavascriptBridge.callHandler('attempt','sub'); parent.postMessage('sent','*');</script>\"></iframe></body></html>" baseURL:nil];
    main.expectedFulfillmentCount = 2;
    [self waitForExpectationsWithTimeout:timeoutSec handler:NULL];
}

- (void)testDefaultScriptRejectsDirectSubframePostMessage {
    WKWebView *webView = [self configuredWebView];
    WebViewJavascriptBridge *bridge = [self bridgeForWebView:webView];
    XCTestExpectation *rejected = [self expectationWithDescription:@"Direct subframe message rejected"];
    rejected.inverted = YES;
    XCTestExpectation *reported = [self expectationWithDescription:@"Subframe attempted direct post"];
    [bridge registerHandler:@"directAttempt" handler:^(WVJBMessageContext *context) {
        [rejected fulfill];
    }];
    [bridge registerHandler:@"reportDirectAttempt" handler:^(WVJBMessageContext *context) {
        XCTAssertTrue(context.frameInfo.isMainFrame);
        XCTAssertEqualObjects(context.data, @"undefined");
        [reported fulfill];
    }];
    [webView loadHTMLString:@"<html><body><script>window.addEventListener('message',function(e){ WebViewJavascriptBridge.callHandler('reportDirectAttempt',e.data); });</script><iframe srcdoc=\"<script>window.webkit.messageHandlers.WebViewJavascriptBridge.postMessage({handlerName:'directAttempt'}); parent.postMessage(typeof WebViewJavascriptBridge,'*');</script>\"></iframe></body></html>" baseURL:nil];
    [self waitForExpectationsWithTimeout:timeoutSec handler:NULL];
}

- (void)testAuthorizationHandlerDecidesPerMainFrameHandler {
    WKWebView *webView = [self configuredWebView];
    WebViewJavascriptBridge *bridge = [self bridgeForWebView:webView];
    XCTestExpectation *decisions = [self expectationWithDescription:@"Authorization saw both main frame handlers"];
    decisions.expectedFulfillmentCount = 2;
    XCTestExpectation *allowed = [self expectationWithDescription:@"Allowed main frame handler ran"];
    XCTestExpectation *denied = [self expectationWithDescription:@"Denied main frame handler did not run"];
    denied.inverted = YES;
    bridge.authorizationHandler = ^BOOL(WVJBMessageContext *context, NSString *handlerName) {
        XCTAssertTrue(context.frameInfo.isMainFrame);
        if ([handlerName isEqualToString:@"deniedMain"] || [handlerName isEqualToString:@"allowedMain"]) {
            XCTAssertEqualObjects(context.data, handlerName);
            [decisions fulfill];
        } else {
            XCTFail(@"Unexpected handler: %@", handlerName);
        }
        return [handlerName isEqualToString:@"allowedMain"];
    };
    [bridge registerHandler:@"deniedMain" handler:^(WVJBMessageContext *context) {
        [denied fulfill];
    }];
    [bridge registerHandler:@"allowedMain" handler:^(WVJBMessageContext *context) {
        XCTAssertTrue(context.frameInfo.isMainFrame);
        XCTAssertEqualObjects(context.data, @"allowedMain");
        [allowed fulfill];
    }];
    [webView loadHTMLString:@"<html><body><script>WebViewJavascriptBridge.callHandler('deniedMain','deniedMain'); WebViewJavascriptBridge.callHandler('allowedMain','allowedMain');</script></body></html>" baseURL:nil];
    [self waitForExpectationsWithTimeout:timeoutSec handler:NULL];
}

- (void)testRemovedSubframeAsyncReplyIsNotDeliveredToMainFrame {
    WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
    [configuration.userContentController addUserScript:[WebViewJavascriptBridge userScriptForMainFrameOnly:NO]];
    WKWebView *webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
    WebViewJavascriptBridge *bridge = [WebViewJavascriptBridge bridgeForWebView:webView];
    [_retains addObjectsFromArray:@[webView, bridge]];
    bridge.authorizationHandler = ^BOOL(WVJBMessageContext *context, NSString *handlerName) { return YES; };
    XCTestExpectation *removed = [self expectationWithDescription:@"Subframe removed before asynchronous reply"];
    XCTestExpectation *checked = [self expectationWithDescription:@"Main frame checked after reply"];
    [bridge registerHandler:@"delayedReply" handler:^(WVJBMessageContext *context) {
        XCTAssertFalse(context.frameInfo.isMainFrame);
        XCTAssertEqualObjects(context.data, @"subframe request");
        [webView evaluateJavaScript:@"document.getElementById('child').remove(); !document.getElementById('child');" completionHandler:^(id result, NSError *error) {
            XCTAssertNil(error);
            XCTAssertEqualObjects(result, @YES);
            [removed fulfill];
            context.responseCallback(@"late reply");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [webView evaluateJavaScript:@"window.misdirectedReplies" completionHandler:^(id count, NSError *checkError) {
                    XCTAssertNil(checkError);
                    XCTAssertEqualObjects(count, @0);
                    [checked fulfill];
                }];
            });
        }];
    }];
    [webView loadHTMLString:@"<html><body><script>window.misdirectedReplies=0; var original=WebViewJavascriptBridge._handleMessageFromObjC; WebViewJavascriptBridge._handleMessageFromObjC=function(message){ if(JSON.parse(message).responseId==='removed-frame-callback') window.misdirectedReplies++; return original(message); };</script><iframe id='child' srcdoc=\"<script>window.webkit.messageHandlers.WebViewJavascriptBridge.postMessage({handlerName:'delayedReply',data:'subframe request',callbackId:'removed-frame-callback'});</script>\"></iframe></body></html>" baseURL:nil];
    [self waitForExpectationsWithTimeout:timeoutSec handler:NULL];
}

- (void)testAuthorizedSubframeReceivesReplyInOriginatingFrame {
    WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
    [configuration.userContentController addUserScript:[WebViewJavascriptBridge userScriptForMainFrameOnly:NO]];
    WKWebView *webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
    WebViewJavascriptBridge *bridge = [WebViewJavascriptBridge bridgeForWebView:webView];
    [_retains addObjectsFromArray:@[webView, bridge]];
    bridge.authorizationHandler = ^BOOL(WVJBMessageContext *context, NSString *handlerName) {
        return context.frameInfo.isMainFrame || [handlerName isEqualToString:@"echoSubframe"];
    };
    XCTestExpectation *reply = [self expectationWithDescription:@"Reply received by iframe"];
    [bridge registerHandler:@"echoSubframe" handler:^(WVJBMessageContext *context) {
        XCTAssertNotNil(context.frameInfo);
        XCTAssertFalse(context.frameInfo.isMainFrame);
        XCTAssertEqualObjects(context.data, @"request");
        context.responseCallback(@"iframe reply");
    }];
    [bridge registerHandler:@"report" handler:^(WVJBMessageContext *context) {
        XCTAssertTrue(context.frameInfo.isMainFrame);
        XCTAssertEqualObjects(context.data, @"iframe reply");
        [reply fulfill];
    }];
    [webView loadHTMLString:@"<html><body><script>window.addEventListener('message', function(e) { WebViewJavascriptBridge.callHandler('report', e.data); });</script><iframe srcdoc=\"<script>WebViewJavascriptBridge.callHandler('echoSubframe','request',function(value){ parent.postMessage(value,'*'); });</script>\"></iframe></body></html>" baseURL:nil];
    [self waitForExpectationsWithTimeout:timeoutSec handler:NULL];
}

- (void)testSubframeCannotForgeMainFrameResponse {
    WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
    [configuration.userContentController addUserScript:[WebViewJavascriptBridge userScriptForMainFrameOnly:NO]];
    WKWebView *webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
    WebViewJavascriptBridge *bridge = [WebViewJavascriptBridge bridgeForWebView:webView];
    [_retains addObjectsFromArray:@[webView, bridge]];
    bridge.authorizationHandler = ^BOOL(WVJBMessageContext *context, NSString *handlerName) { return YES; };
    XCTestExpectation *response = [self expectationWithDescription:@"Legitimate main frame response"];
    XCTestExpectation *forgerySent = [self expectationWithDescription:@"Subframe sent forged response"];
    [bridge registerHandler:@"forgerySent" handler:^(WVJBMessageContext *context) {
        XCTAssertFalse(context.frameInfo.isMainFrame);
        [forgerySent fulfill];
        [webView evaluateJavaScript:@"window.pendingResponse('legitimate')" completionHandler:^(id result, NSError *error) {
            XCTAssertNil(error);
        }];
    }];
    [bridge registerHandler:@"readyForForgery" handler:^(WVJBMessageContext *context) {
        XCTAssertTrue(context.frameInfo.isMainFrame);
        NSString *javascript = @"var f=document.createElement('iframe'); f.srcdoc=\"<script>window.webkit.messageHandlers.WebViewJavascriptBridge.postMessage({responseId:'objc_cb_1',responseData:'forged'}); WebViewJavascriptBridge.callHandler('forgerySent');</script>\"; document.body.appendChild(f); true;";
        [webView evaluateJavaScript:javascript completionHandler:^(id result, NSError *error) { XCTAssertNil(error); }];
    }];
    TestWebPageLoadDelegate *delegate = [TestWebPageLoadDelegate new];
    [_retains addObject:delegate];
    webView.navigationDelegate = delegate;
    delegate.onFinish = ^(WKWebView *loadedWebView) {
        [bridge callHandler:@"hold" data:nil responseCallback:^(id data) {
            XCTAssertEqualObjects(data, @"legitimate");
            [response fulfill];
        }];
    };
    [webView loadHTMLString:@"<html><body><script>WebViewJavascriptBridge.registerHandler('hold',function(data,callback){ window.pendingResponse=callback; WebViewJavascriptBridge.callHandler('readyForForgery'); });</script></body></html>" baseURL:nil];
    [self waitForExpectationsWithTimeout:timeoutSec handler:NULL];
}

- (void)testResponseCallbackIsRemovedAfterDelivery {
    WebViewJavascriptBridgeBase *base = [WebViewJavascriptBridgeBase new];
    __block id received = nil;
    [base sendData:nil responseCallback:^(id data) { received = data; } handlerName:@"test"];
    NSString *callbackID = [base.responseCallbacks.allKeys firstObject];
    XCTAssertNotNil(callbackID);
    [base handleMessage:@{ @"responseId": callbackID, @"responseData": @"ok" } frameInfo:[self testMainFrameInfo]];
    XCTAssertEqualObjects(received, @"ok");
    XCTAssertEqual(base.responseCallbacks.count, 0u);
}

- (void)testUnknownResponseDoesNotCrash {
    WebViewJavascriptBridgeBase *base = [WebViewJavascriptBridgeBase new];
    NSDictionary *message = @{ @"responseId": @"missing", @"responseData": @"ignored" };
    XCTAssertNoThrow([base handleMessage:message frameInfo:[self testMainFrameInfo]]);
}

- (void)testJSONStringMessageBody {
    WebViewJavascriptBridgeBase *base = [WebViewJavascriptBridgeBase new];
    base.delegate = self;
    __block id received = nil;
    base.messageHandlers[@"stringMessage"] = ^(WVJBMessageContext *context) {
        received = context.data;
    };
    [base handleMessage:@"{\"handlerName\":\"stringMessage\",\"data\":\"hello\"}" frameInfo:[self testMainFrameInfo]];
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

    [bridge registerHandler:@"objcEcho" handler:^(WVJBMessageContext *context) {
        XCTAssertEqualObjects(context.data, @"string parameter");
        context.responseCallback(context.data);
    }];
    [bridge registerHandler:@"reportResponse" handler:^(WVJBMessageContext *context) {
        XCTAssertEqualObjects(context.data, @"string parameter");
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
    [configuration.userContentController addUserScript:[WebViewJavascriptBridge userScriptForMainFrameOnly:YES]];
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
    [configurationA.userContentController addUserScript:[WebViewJavascriptBridge userScriptForMainFrameOnly:YES]];
    WKWebViewConfiguration *configurationB = [WKWebViewConfiguration new];
    [configurationB.userContentController addUserScript:[WebViewJavascriptBridge userScriptForMainFrameOnly:YES]];
    WKWebView *webViewA = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configurationA];
    WKWebView *webViewB = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configurationB];
    [_retains addObject:webViewA];
    [_retains addObject:webViewB];
    WebViewJavascriptBridge *bridgeA = [WebViewJavascriptBridge bridgeForWebView:webViewA];
    WebViewJavascriptBridge *bridgeB = [WebViewJavascriptBridge bridgeForWebView:webViewB];
    [_retains addObjectsFromArray:@[bridgeA, bridgeB]];
    XCTestExpectation *callbackA = [self expectationWithDescription:@"First web view callback invoked"];
    XCTestExpectation *callbackB = [self expectationWithDescription:@"Second web view callback invoked"];

    [bridgeA registerHandler:@"isolatedHandler" handler:^(WVJBMessageContext *context) {
        XCTAssertEqualObjects(context.data, @"A");
        context.responseCallback(@"response A");
    }];
    [bridgeB registerHandler:@"isolatedHandler" handler:^(WVJBMessageContext *context) {
        XCTAssertEqualObjects(context.data, @"B");
        context.responseCallback(@"response B");
    }];
    [bridgeA registerHandler:@"reportResponse" handler:^(WVJBMessageContext *context) {
        XCTAssertEqualObjects(context.data, @"response A");
        [callbackA fulfill];
    }];
    [bridgeB registerHandler:@"reportResponse" handler:^(WVJBMessageContext *context) {
        XCTAssertEqualObjects(context.data, @"response B");
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
    [configuration.userContentController addUserScript:[WebViewJavascriptBridge userScriptForMainFrameOnly:YES]];
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
