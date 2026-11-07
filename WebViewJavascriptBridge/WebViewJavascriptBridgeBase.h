//
//  WebViewJavascriptBridgeBase.h
//
//  Created by @LokiMeyburg on 10/15/14.
//  Copyright (c) 2014 @LokiMeyburg. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^WVJBResponseCallback)(id responseData);
typedef void (^WVJBHandler)(id data, WVJBResponseCallback responseCallback);
typedef NSDictionary WVJBMessage;

@protocol WebViewJavascriptBridgeBaseDelegate <NSObject>
- (void)wvjb_evaluateJavascript:(NSString *)javascriptCommand completionHandler:(void (^ _Nullable)(_Nullable id, NSError * _Nullable error))completionHandler;
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
- (void)handleMessage:(id)message;
- (void)handleMessage:(id)message fromMainFrame:(BOOL)fromMainFrame;
- (void)bridgeDidBecomeReady;
- (void)disableJavscriptAlertBoxSafetyTimeout;

@end
NS_ASSUME_NONNULL_END
