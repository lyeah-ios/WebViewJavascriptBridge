//
//  WebViewJavascriptBridgeBase.h
//
//  Created by @LokiMeyburg on 10/15/14.
//  Copyright (c) 2014 @LokiMeyburg. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^WVJBResponseCallback)(id responseData);
@interface WVJBMessageContext : NSObject
@property (nullable, nonatomic, strong, readonly) id data;
@property (nonatomic, strong, readonly) WKFrameInfo *frameInfo;
/// Nil when the JavaScript call did not include a response callback.
@property (nullable, nonatomic, copy, readonly) WVJBResponseCallback responseCallback;
- (instancetype)init NS_UNAVAILABLE;
@end

typedef void (^WVJBHandler)(WVJBMessageContext *context);
typedef BOOL (^WVJBAuthorizationHandler)(WVJBMessageContext *context, NSString *handlerName);
typedef NSDictionary WVJBMessage;

@protocol WebViewJavascriptBridgeBaseDelegate <NSObject>
- (void)wvjb_evaluateJavascript:(NSString *)javascriptCommand inFrame:(nullable WKFrameInfo *)frame completionHandler:(void (^ _Nullable)(_Nullable id, NSError * _Nullable error))completionHandler;
- (BOOL)wvjb_authorizeContext:(WVJBMessageContext *)context handlerName:(NSString *)handlerName;
@end

@interface WebViewJavascriptBridgeBase : NSObject

@property (nonatomic, weak) id <WebViewJavascriptBridgeBaseDelegate> delegate;
@property (nullable, nonatomic, strong) NSMutableArray *startupMessageQueue;
@property (nullable, nonatomic, strong) NSMutableDictionary *responseCallbacks;
@property (nullable, nonatomic, strong) NSMutableDictionary *messageHandlers;

+ (void)enableLogging;
+ (void)setLogMaxLength:(int)length;
- (void)reset;
- (void)sendData:(nullable id)data responseCallback:(nullable WVJBResponseCallback)responseCallback handlerName:(NSString *)handlerName;
- (void)handleMessage:(id)message frameInfo:(WKFrameInfo *)frameInfo;
- (void)bridgeDidBecomeReady;
- (void)disableJavscriptAlertBoxSafetyTimeout;

@end
NS_ASSUME_NONNULL_END
