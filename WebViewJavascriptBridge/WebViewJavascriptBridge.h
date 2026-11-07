//
//  WebViewJavascriptBridge.h
//  ExampleApp-iOS
//
//  Created by Marcus Westin on 6/14/13.
//  Copyright (c) 2013 Marcus Westin. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>
#import "WebViewJavascriptBridgeBase.h"

NS_ASSUME_NONNULL_BEGIN

@protocol WebViewJavascriptBridge <NSObject>

- (void)registerHandler:(NSString *)handlerName handler:(WVJBHandler)handler;
- (void)removeHandler:(NSString *)handlerName;
/// Bridge readiness does not guarantee that application JavaScript handlers are registered.
/// During navigation or reload, in-flight calls and responses may be lost or reach the wrong document.
/// Each subsequent main-frame ready signal clears all native pending response callbacks without
/// invoking them or reporting an error. Coordinate calls with application-level readiness.
- (void)callHandler:(NSString *)handlerName;
- (void)callHandler:(NSString *)handlerName data:(nullable id)data;
- (void)callHandler:(NSString *)handlerName data:(nullable id)data responseCallback:(nullable WVJBResponseCallback)responseCallback;

@end

@interface WebViewJavascriptBridge : NSObject<WebViewJavascriptBridge, WebViewJavascriptBridgeBaseDelegate>

/// Return the document-start, main-frame-only script. The business must add it to the
/// configuration's userContentController before creating the WKWebView.
+ (WKUserScript *)userScript;

/// Return the document-start script with the requested frame scope. All-frame injection
/// does not provide frame-specific replies; native replies are evaluated in the main frame.
+ (WKUserScript *)userScriptForMainFrameOnly:(BOOL)mainFrameOnly;

/// Bridge state is not synchronized for concurrent access.
/// A matching userScript with either frame scope must be added before creating the WKWebView.
/// The user content controller must not have another active bridge or a handler
/// named WebViewJavascriptBridge. WebKit may raise an exception on a conflict.
+ (nullable instancetype)bridgeForWebView:(nullable WKWebView *)webView;

+ (void)enableLogging;
+ (void)setLogMaxLength:(int)length;

- (void)disableJavscriptAlertBoxSafetyTimeout;

@end

NS_ASSUME_NONNULL_END
