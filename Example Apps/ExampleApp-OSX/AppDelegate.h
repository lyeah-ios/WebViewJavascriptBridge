//
//  AppDelegate.h
//  ExampleApp-OSX
//
//  Created by Marcus Westin on 6/8/13.
//  Copyright (c) 2013 Marcus Westin. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

@interface AppDelegate : NSObject <NSApplicationDelegate, WKNavigationDelegate>

@property (assign) IBOutlet NSWindow *window;
@property (assign) IBOutlet NSView *WKWebViewWrapper;

@end
