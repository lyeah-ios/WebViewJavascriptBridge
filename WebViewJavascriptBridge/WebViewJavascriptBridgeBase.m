//
//  WebViewJavascriptBridgeBase.m
//
//  Created by @LokiMeyburg on 10/15/14.
//  Copyright (c) 2014 @LokiMeyburg. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "WebViewJavascriptBridgeBase.h"

static bool logging = false;
static int logMaxLength = 500;

@interface WVJBMessageContext ()
- (instancetype)initWithData:(id)data frameInfo:(WKFrameInfo *)frameInfo responseCallback:(WVJBResponseCallback)responseCallback;
@end

@implementation WVJBMessageContext
- (instancetype)initWithData:(id)data frameInfo:(WKFrameInfo *)frameInfo responseCallback:(WVJBResponseCallback)responseCallback
{
    self = [super init];
    if (self) {
        _data = data;
        _frameInfo = frameInfo;
        _responseCallback = [responseCallback copy];
    }
    return self;
}
@end

@interface WebViewJavascriptBridgeBase ()
{
    long _uniqueId;
}
+ (void)wvjb_log:(NSString *)action message:(id)message debug:(BOOL)debug;
@end

@implementation WebViewJavascriptBridgeBase

+ (void)enableLogging { logging = true; }
+ (void)setLogMaxLength:(int)length { logMaxLength = MAX(0, length); }

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

- (void)handleMessage:(id)message frameInfo:(WKFrameInfo *)frameInfo
{
    if (!frameInfo) {
        [WebViewJavascriptBridgeBase wvjb_log:@"WARNING" message:@"Rejected message without frame information" debug:NO];
        return;
    }
    if ([message isKindOfClass:[NSString class]]) {
        message = [self wvjb_deserializeMessageJSON:message];
    }
    if (![message isKindOfClass:[NSDictionary class]]) {
        [WebViewJavascriptBridgeBase wvjb_log:@"WARNING" message:@"Invalid message received" debug:NO];
        return;
    }
    NSDictionary *messageDictionary = (NSDictionary *)message;
    id ready = message[@"__wvjbReady"];
    if (ready) {
        if (CFGetTypeID((__bridge CFTypeRef)ready) != CFBooleanGetTypeID()) {
            [WebViewJavascriptBridgeBase wvjb_log:@"WARNING" message:@"Invalid ready flag" debug:NO];
            return;
        }
        if ([ready boolValue] && messageDictionary.count == 1) {
            if (frameInfo.isMainFrame) {
                [self bridgeDidBecomeReady];
            }
            return;
        }
    }
    for (NSString *key in @[@"responseId", @"callbackId", @"handlerName"]) {
        id value = message[key];
        if (value && ![value isKindOfClass:[NSString class]]) {
            [WebViewJavascriptBridgeBase wvjb_log:@"WARNING" message:[NSString stringWithFormat:@"Invalid message field: %@", key] debug:NO];
            return;
        }
    }
    if (!message[@"responseId"] && !message[@"handlerName"]) {
        [WebViewJavascriptBridgeBase wvjb_log:@"WARNING" message:@"Missing handler name" debug:NO];
        return;
    }
    if (message[@"responseId"] && !frameInfo.isMainFrame) {
        [WebViewJavascriptBridgeBase wvjb_log:@"WARNING" message:@"Rejected subframe response" debug:NO];
        return;
    }
    WVJBResponseCallback reply = nil;
    NSString *callbackId = message[@"responseId"] ? nil : message[@"callbackId"];
    if (callbackId) {
        __weak typeof(self) weakSelf = self;
        reply = ^(id responseData) {
            WVJBMessage *response = @{@"responseId": callbackId, @"responseData": responseData ?: [NSNull null]};
            [weakSelf wvjb_dispatchMessage:response frameInfo:frameInfo];
        };
    }
    WVJBMessageContext *context = [[WVJBMessageContext alloc] initWithData:message[@"data"] frameInfo:frameInfo responseCallback:reply];
    if (!message[@"responseId"] && ![self.delegate wvjb_authorizeContext:context handlerName:message[@"handlerName"]]) {
        [WebViewJavascriptBridgeBase wvjb_log:@"WARNING" message:@"Rejected unauthorized handler" debug:NO];
        return;
    }
    [self wvjb_handleMessage:message context:context];
}

- (void)bridgeDidBecomeReady
{
    // The first ready signal releases calls made before document-start ran.
    // Later signals represent a reload; discard callbacks belonging to the old document.
    if (!self.startupMessageQueue) {
        self.startupMessageQueue = [NSMutableArray array];
        self.responseCallbacks = [NSMutableDictionary dictionary];
    }
    NSArray *queue = self.startupMessageQueue;
    self.startupMessageQueue = nil;
    for (id queuedMessage in queue) {
        [self wvjb_dispatchMessage:queuedMessage];
    }
}

- (void)wvjb_handleMessage:(WVJBMessage *)message context:(WVJBMessageContext *)context
{
    if (![message isKindOfClass:[WVJBMessage class]]) {
        [WebViewJavascriptBridgeBase wvjb_log:@"WARNING" message:@"Invalid message received" debug:NO];
        return;
    }
    [WebViewJavascriptBridgeBase wvjb_log:@"RCVD" message:message debug:YES];
        
        NSString *responseId = message[@"responseId"];
        if (responseId) {
            WVJBResponseCallback responseCallback = _responseCallbacks[responseId];
            if (responseCallback) {
                responseCallback(message[@"responseData"]);
            } else {
                [WebViewJavascriptBridgeBase wvjb_log:@"WARNING" message:@"Received response for unknown callback" debug:NO];
            }
            [self.responseCallbacks removeObjectForKey:responseId];
        } else {
            WVJBHandler handler = self.messageHandlers[message[@"handlerName"]];
            
            if (!handler) {
                [WebViewJavascriptBridgeBase wvjb_log:@"WARNING" message:@"No handler for message from JavaScript" debug:NO];
                return;
            }
            
            handler(context);
    }
}

- (void)disableJavscriptAlertBoxSafetyTimeout
{
    [self sendData:nil responseCallback:nil handlerName:@"_disableJavascriptAlertBoxSafetyTimeout"];
}

#pragma mark ---------- Private ----------

- (void)wvjb_queueMessage:(WVJBMessage*)message
{
    BOOL isResponse = message[@"responseId"] != nil;
    if (self.startupMessageQueue && !isResponse) {
        [self.startupMessageQueue addObject:message];
    } else {
        [self wvjb_dispatchMessage:message];
    }
}

- (void)wvjb_dispatchMessage:(WVJBMessage *)message
{
    [self wvjb_dispatchMessage:message frameInfo:nil];
}

- (void)wvjb_dispatchMessage:(WVJBMessage *)message frameInfo:(WKFrameInfo *)frameInfo
{
    NSString *messageJSON = [self wvjb_serializeMessage:message pretty:NO];
    [WebViewJavascriptBridgeBase wvjb_log:@"SEND" message:messageJSON debug:YES];
    messageJSON = [messageJSON stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    messageJSON = [messageJSON stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    messageJSON = [messageJSON stringByReplacingOccurrencesOfString:@"\'" withString:@"\\\'"];
    messageJSON = [messageJSON stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
    messageJSON = [messageJSON stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"];
    messageJSON = [messageJSON stringByReplacingOccurrencesOfString:@"\f" withString:@"\\f"];
    messageJSON = [messageJSON stringByReplacingOccurrencesOfString:@"\u2028" withString:@"\\u2028"];
    messageJSON = [messageJSON stringByReplacingOccurrencesOfString:@"\u2029" withString:@"\\u2029"];
    
    NSString *javascriptCommand = [NSString stringWithFormat:@"WebViewJavascriptBridge._handleMessageFromObjC('%@');", messageJSON];
    void (^evaluate)(void) = ^{
        [self.delegate wvjb_evaluateJavascript:javascriptCommand inFrame:frameInfo completionHandler:^(id result, NSError *error) {
            if (error) {
                [WebViewJavascriptBridgeBase wvjb_log:@"ERROR" message:[NSString stringWithFormat:@"JavaScript evaluation failed (code %ld)", (long)error.code] debug:NO];
            }
        }];
    };
    if ([NSThread isMainThread]) {
        evaluate();
    } else {
        dispatch_sync(dispatch_get_main_queue(), evaluate);
    }
}

- (NSString *)wvjb_serializeMessage:(id)message pretty:(BOOL)pretty
{
    return [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:message options:(NSJSONWritingOptions)(pretty ? NSJSONWritingPrettyPrinted : 0) error:nil] encoding:NSUTF8StringEncoding];
}

- (NSArray *)wvjb_deserializeMessageJSON:(NSString *)messageJSON
{
    NSData *data = [messageJSON dataUsingEncoding:NSUTF8StringEncoding];
    return data ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:nil] : nil;
}

+ (void)wvjb_log:(NSString *)action message:(id)message debug:(BOOL)debug
{
    if (debug && !logging) { return; }
    NSString *text = message;
    if (![message isKindOfClass:[NSString class]]) {
        NSData *data = [NSJSONSerialization isValidJSONObject:message] ? [NSJSONSerialization dataWithJSONObject:message options:NSJSONWritingPrettyPrinted error:nil] : nil;
        text = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"<unserializable>";
    }
    if (debug && text.length > (NSUInteger)logMaxLength) {
        NSUInteger end = (NSUInteger)logMaxLength;
        if (end > 0 && end < text.length && CFStringIsSurrogateHighCharacter([text characterAtIndex:end - 1]) && CFStringIsSurrogateLowCharacter([text characterAtIndex:end])) {
            end--;
        }
        text = [[text substringToIndex:end] stringByAppendingString:@" [...]"];
    }
    NSLog(@"WVJB %@: %@", action, text);
}

@end
