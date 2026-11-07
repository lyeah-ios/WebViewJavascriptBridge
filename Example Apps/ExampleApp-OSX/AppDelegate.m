//
//  AppDelegate.m
//  ExampleApp-OSX
//
//  Created by Marcus Westin on 6/8/13.
//  Copyright (c) 2013 Marcus Westin. All rights reserved.
//

#import "AppDelegate.h"
#import <WebKit/WebKit.h>
#import "WebViewJavascriptBridge.h"

@implementation AppDelegate {
    WKWebView *_WKWebView;
    WebViewJavascriptBridge* _WKBridge;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    [self _configureWKWebview];
}

- (void)_configureWKWebview {
    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    [configuration.userContentController addUserScript:[WebViewJavascriptBridge userScript]];
    _WKWebView = [[WKWebView alloc] initWithFrame:self.WKWebViewWrapper.bounds configuration:configuration];
    _WKBridge = [WebViewJavascriptBridge bridgeForWebView:_WKWebView];
    _WKWebView.navigationDelegate = self;
    [_WKWebView setAutoresizingMask:(NSViewHeightSizable | NSViewWidthSizable)];
    [self.WKWebViewWrapper addSubview:_WKWebView];

    [_WKBridge registerHandler:@"testObjcCallback" handler:^(id data, WVJBResponseCallback responseCallback) {
        NSLog(@"testObjcCallback called: %@", data);
        responseCallback(@"Response from testObjcCallback");
    }];
    
    [_WKBridge callHandler:@"testJavascriptHandler" data:@{ @"foo":@"before ready" }];
    
    // Create Buttons
    NSButton *callbackButton = [[NSButton alloc] initWithFrame:NSMakeRect(5, 0, 120, 40)];
    [callbackButton setTitle:@"Call handler"];
    [callbackButton setBezelStyle:NSRoundedBezelStyle];
    [callbackButton setTarget:self];
    [callbackButton setAction:@selector(_WKCallHandler)];
    [_WKWebView addSubview:callbackButton];
    
    NSButton *webViewToggleButton = [[NSButton alloc] initWithFrame:NSMakeRect(120, 0, 180, 40)];
    [webViewToggleButton setTitle:@"Switch to WebView"];
    [webViewToggleButton setBezelStyle:NSRoundedBezelStyle];
    [webViewToggleButton setTarget:self];
    [webViewToggleButton setAction:@selector(_toggleExample)];
    [_WKWebView addSubview:webViewToggleButton];
    
    // Load Page
    NSString* htmlPath = [[NSBundle mainBundle] pathForResource:@"ExampleApp" ofType:@"html"];
    NSString* html = [NSString stringWithContentsOfFile:htmlPath encoding:NSUTF8StringEncoding error:nil];
    NSURL *baseURL = [NSURL fileURLWithPath:htmlPath];
    [_WKWebView loadHTMLString:html baseURL:baseURL];
}

-(void)_toggleExample {
    _WKWebView.hidden = !_WKWebView.isHidden;
}

- (void)_WKCallHandler {
    id data = @{ @"greetingFromObjC": @"Hi there, JS!" };
    [_WKBridge callHandler:@"testJavascriptHandler" data:data responseCallback:^(id response) {
        NSLog(@"testJavascriptHandler responded: %@", response);
    }];
}

@end
