//
//  WebViewJavascriptBridgeBase.m
//
//  Created by @LokiMeyburg on 10/15/14.
//  Copyright (c) 2014 @LokiMeyburg. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "WebViewJavascriptBridgeBase.h"
#import "WebViewJavascriptBridge_JS.h"

static bool logging = false;
static int logMaxLength = 500;

@interface WebViewJavascriptBridgeBase ()
{
    long _uniqueId;
}

@end

@implementation WebViewJavascriptBridgeBase

+ (void)enableLogging { logging = true; }
+ (void)setLogMaxLength:(int)length { logMaxLength = length;}

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.messageHandlers = [NSMutableDictionary dictionary];
        self.startupMessageQueue = [NSMutableArray array];
        self.responseCallbacks = [NSMutableDictionary dictionary];
        _uniqueId = 0;
    }
    return self;
}

- (void)dealloc
{
    self.startupMessageQueue = nil;
    self.responseCallbacks = nil;
    self.messageHandlers = nil;
}

#pragma mark ---------- Public ----------

- (void)reset
{
    self.startupMessageQueue = [NSMutableArray array];
    self.responseCallbacks = [NSMutableDictionary dictionary];
    _uniqueId = 0;
}

- (void)sendData:(id)data responseCallback:(WVJBResponseCallback)responseCallback handlerName:(NSString*)handlerName
{
    NSMutableDictionary *message = [NSMutableDictionary dictionary];
    
    if (data) {
        message[@"data"] = data;
    }
    
    if (responseCallback) {
        NSString *callbackId = [NSString stringWithFormat:@"objc_cb_%ld", ++_uniqueId];
        self.responseCallbacks[callbackId] = [responseCallback copy];
        message[@"callbackId"] = callbackId;
    }
    
    if (handlerName) {
        message[@"handlerName"] = handlerName;
    }
    [self wvjb_queueMessage:message];
}

- (void)flushMessageQueue:(NSString *)messageQueueString
{
    if (messageQueueString == nil || messageQueueString.length == 0) {
        NSLog(@"WebViewJavascriptBridge: WARNING: ObjC got nil while fetching the message queue JSON from webview. This can happen if the WebViewJavascriptBridge JS is not currently present in the webview, e.g if the webview just loaded a new page.");
        return;
    }
    
    id messages = [self wvjb_deserializeMessageJSON:messageQueueString];
    for (WVJBMessage *message in messages) {
        if (![message isKindOfClass:[WVJBMessage class]]) {
            NSLog(@"WebViewJavascriptBridge: WARNING: Invalid %@ received: %@", [message class], message);
            continue;
        }
        [self wvjb_log:@"RCVD" json:message];
        
        NSString *responseId = message[@"responseId"];
        if (responseId) {
            WVJBResponseCallback responseCallback = _responseCallbacks[responseId];
            responseCallback(message[@"responseData"]);
            [self.responseCallbacks removeObjectForKey:responseId];
        } else {
            WVJBResponseCallback responseCallback = NULL;
            NSString *callbackId = message[@"callbackId"];
            if (callbackId) {
                responseCallback = ^(id responseData) {
                    if (responseData == nil) {
                        responseData = [NSNull null];
                    }
                    
                    WVJBMessage *msg = @{ @"responseId":callbackId, @"responseData":responseData };
                    [self wvjb_queueMessage:msg];
                };
            } else {
                responseCallback = ^(id ignoreResponseData) {
                    // Do nothing
                };
            }
            
            WVJBHandler handler = self.messageHandlers[message[@"handlerName"]];
            
            if (!handler) {
                NSLog(@"WVJBNoHandlerException, No handler for message from JS: %@", message);
                continue;
            }
            
            handler(message[@"data"], responseCallback);
        }
    }
}

- (void)injectJavascriptFile
{
    NSString *js = WebViewJavascriptBridge_js();
    [self wvjb_evaluateJavascript:js];
    if (self.startupMessageQueue) {
        NSArray *queue = self.startupMessageQueue;
        self.startupMessageQueue = nil;
        for (id queuedMessage in queue) {
            [self wvjb_dispatchMessage:queuedMessage];
        }
    }
}

- (BOOL)isWebViewJavascriptBridgeURL:(NSURL *)url
{
    if (![self isSchemeMatch:url]) {
        return NO;
    }
    return [self isBridgeLoadedURL:url] || [self isQueueMessageURL:url];
}

- (BOOL)isSchemeMatch:(NSURL *)url
{
    NSString *scheme = url.scheme.lowercaseString;
    return [scheme isEqualToString:kWVJBProtocolScheme];
}

- (BOOL)isQueueMessageURL:(NSURL *)url
{
    NSString *host = url.host.lowercaseString;
    return [self isSchemeMatch:url] && [host isEqualToString:kQueueHasMessage];
}

- (BOOL)isBridgeLoadedURL:(NSURL *)url
{
    NSString *host = url.host.lowercaseString;
    return [self isSchemeMatch:url] && [host isEqualToString:kBridgeLoaded];
}

- (void)logUnkownMessage:(NSURL *)url
{
    NSLog(@"WebViewJavascriptBridge: WARNING: Received unknown WebViewJavascriptBridge command %@", [url absoluteString]);
}

- (NSString *)webViewJavascriptCheckCommand
{
    return @"typeof WebViewJavascriptBridge == \'object\';";
}

- (NSString *)webViewJavascriptFetchQueyCommand
{
    return @"WebViewJavascriptBridge._fetchQueue();";
}

- (void)disableJavscriptAlertBoxSafetyTimeout
{
    [self sendData:nil responseCallback:nil handlerName:@"_disableJavascriptAlertBoxSafetyTimeout"];
}

#pragma mark ---------- Private ----------

- (void)wvjb_evaluateJavascript:(NSString *)javascriptCommand
{
    [self.delegate wvjb_evaluateJavascript:javascriptCommand completionHandler:^(id _Nullable result, NSError * _Nullable error) {
        
    }];
}

- (void)wvjb_queueMessage:(WVJBMessage*)message
{
    if (self.startupMessageQueue) {
        [self.startupMessageQueue addObject:message];
    } else {
        [self wvjb_dispatchMessage:message];
    }
}

- (void)wvjb_dispatchMessage:(WVJBMessage *)message
{
    NSString *messageJSON = [self wvjb_serializeMessage:message pretty:NO];
    [self wvjb_log:@"SEND" json:messageJSON];
    messageJSON = [messageJSON stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    messageJSON = [messageJSON stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    messageJSON = [messageJSON stringByReplacingOccurrencesOfString:@"\'" withString:@"\\\'"];
    messageJSON = [messageJSON stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
    messageJSON = [messageJSON stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"];
    messageJSON = [messageJSON stringByReplacingOccurrencesOfString:@"\f" withString:@"\\f"];
    messageJSON = [messageJSON stringByReplacingOccurrencesOfString:@"\u2028" withString:@"\\u2028"];
    messageJSON = [messageJSON stringByReplacingOccurrencesOfString:@"\u2029" withString:@"\\u2029"];
    
    NSString* javascriptCommand = [NSString stringWithFormat:@"WebViewJavascriptBridge._handleMessageFromObjC('%@');", messageJSON];
    if ([[NSThread currentThread] isMainThread]) {
        [self wvjb_evaluateJavascript:javascriptCommand];
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            [self wvjb_evaluateJavascript:javascriptCommand];
        });
    }
}

- (NSString *)wvjb_serializeMessage:(id)message pretty:(BOOL)pretty
{
    return [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:message options:(NSJSONWritingOptions)(pretty ? NSJSONWritingPrettyPrinted : 0) error:nil] encoding:NSUTF8StringEncoding];
}

- (NSArray *)wvjb_deserializeMessageJSON:(NSString *)messageJSON
{
    return [NSJSONSerialization JSONObjectWithData:[messageJSON dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingAllowFragments error:nil];
}

- (void)wvjb_log:(NSString *)action json:(id)json
{
    if (!logging) { return; }
    if (![json isKindOfClass:[NSString class]]) {
        json = [self wvjb_serializeMessage:json pretty:YES];
    }
    if ([json length] > logMaxLength) {
        NSLog(@"WVJB %@: %@ [...]", action, [json substringToIndex:logMaxLength]);
    } else {
        NSLog(@"WVJB %@: %@", action, json);
    }
}

@end
