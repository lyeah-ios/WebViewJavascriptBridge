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
- (void)callHandler:(NSString *)handlerName;
- (void)callHandler:(NSString *)handlerName data:(nullable id)data;
- (void)callHandler:(NSString *)handlerName data:(nullable id)data responseCallback:(nullable WVJBResponseCallback)responseCallback;

@end

@interface WebViewJavascriptBridge : NSObject<WKNavigationDelegate, WebViewJavascriptBridge, WebViewJavascriptBridgeBaseDelegate>

+ (instancetype)bridgeForWebView:(WKWebView *)webView;

+ (void)enableLogging;
+ (void)setLogMaxLength:(int)length;

- (void)setWebViewDelegate:(id)webViewDelegate;
- (void)disableJavscriptAlertBoxSafetyTimeout;

@end

NS_ASSUME_NONNULL_END
