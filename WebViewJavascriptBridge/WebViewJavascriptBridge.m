//
//  WebViewJavascriptBridge.m
//  ExampleApp-iOS
//
//  Created by Marcus Westin on 6/14/13.
//  Copyright (c) 2013 Marcus Westin. All rights reserved.
//

#import "WebViewJavascriptBridge.h"
#import "WebViewJavascriptBridge_JS.h"

static NSString * const kWVJBScriptMessageHandlerName = @"WebViewJavascriptBridge";

@class WebViewJavascriptBridge;

@interface WVJBScriptMessageRouter : NSObject <WKScriptMessageHandler>
@property (nonatomic, weak) WebViewJavascriptBridge *bridge;
@end

@interface WebViewJavascriptBridge ()
{
    __weak WKWebView *_webView;
    __weak WKUserContentController *_userContentController;
    WebViewJavascriptBridgeBase *_base;
}
- (void)wvjb_receiveMessage:(WKScriptMessage *)message;
@end

@implementation WVJBScriptMessageRouter

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message
{
    [self.bridge wvjb_receiveMessage:message];
}

@end

@implementation WebViewJavascriptBridge

#pragma mark ---------- initialize ----------

+ (WKUserScript *)userScript
{
    return [self userScriptForMainFrameOnly:YES];
}

+ (WKUserScript *)userScriptForMainFrameOnly:(BOOL)mainFrameOnly
{
    return [[WKUserScript alloc] initWithSource:WebViewJavascriptBridge_js()
                                  injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                               forMainFrameOnly:mainFrameOnly];
}

+ (instancetype)bridgeForWebView:(WKWebView *)webView
{
    if (!webView) {
        NSLog(@"WebViewJavascriptBridge: webView must not be nil");
        return nil;
    }

    WKUserContentController *userContentController = webView.configuration.userContentController;
    BOOL hasMatchingScript = NO;
    NSString *source = WebViewJavascriptBridge_js();
    for (WKUserScript *script in userContentController.userScripts) {
        if ([script.source isEqualToString:source] &&
            script.injectionTime == WKUserScriptInjectionTimeAtDocumentStart) {
            hasMatchingScript = YES;
            break;
        }
    }
    if (!hasMatchingScript) {
        NSLog(@"WebViewJavascriptBridge: matching userScript was not injected; add +[WebViewJavascriptBridge userScript] or +[WebViewJavascriptBridge userScriptForMainFrameOnly:] before creating the WKWebView");
        return nil;
    }

    WebViewJavascriptBridge *bridge = [[self alloc] init];
    bridge->_base = [[WebViewJavascriptBridgeBase alloc] init];
    bridge->_base.delegate = bridge;
    bridge->_webView = webView;
    WVJBScriptMessageRouter *router = [[WVJBScriptMessageRouter alloc] init];
    router.bridge = bridge;
    [userContentController addScriptMessageHandler:router name:kWVJBScriptMessageHandlerName];
    bridge->_userContentController = userContentController;
    return bridge;
}

#pragma mark ---------- Log ----------

+ (void)enableLogging
{
    [WebViewJavascriptBridgeBase enableLogging];
}

+ (void)setLogMaxLength:(int)length
{
    [WebViewJavascriptBridgeBase setLogMaxLength:length];
}

#pragma mark ---------- WebViewJavascriptBridge ----------

- (void)callHandler:(NSString *)handlerName
{
    [self callHandler:handlerName data:nil responseCallback:nil];
}

- (void)callHandler:(NSString *)handlerName data:(id)data
{
    [self callHandler:handlerName data:data responseCallback:nil];
}

- (void)callHandler:(NSString *)handlerName data:(id)data responseCallback:(WVJBResponseCallback)responseCallback
{
    [_base sendData:data responseCallback:responseCallback handlerName:handlerName];
}

- (void)registerHandler:(NSString *)handlerName handler:(WVJBHandler)handler
{
    _base.messageHandlers[handlerName] = [handler copy];
}

- (void)removeHandler:(NSString *)handlerName
{
    [_base.messageHandlers removeObjectForKey:handlerName];
}

#pragma mark ---------- API ----------

- (void)disableJavscriptAlertBoxSafetyTimeout
{
    [_base disableJavscriptAlertBoxSafetyTimeout];
}

- (void)dealloc
{
    [_userContentController removeScriptMessageHandlerForName:kWVJBScriptMessageHandlerName];
}

#pragma mark ---------- WebViewJavascriptBridgeBaseDelegate ----------

- (void)wvjb_evaluateJavascript:(NSString *)javascriptCommand completionHandler:(void (^)(id _Nullable, NSError * _Nullable))completionHandler
{
    [_webView evaluateJavaScript:javascriptCommand completionHandler:completionHandler];
}

- (void)wvjb_receiveMessage:(WKScriptMessage *)message
{
    if (message.webView == _webView && _webView) {
        [_base handleMessage:message.body fromMainFrame:message.frameInfo.isMainFrame];
    }
}

@end
