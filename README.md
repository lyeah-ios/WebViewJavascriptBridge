WebViewJavascriptBridge
=======================

[![Circle CI](https://img.shields.io/circleci/project/github/marcuswestin/WebViewJavascriptBridge.svg)](https://circleci.com/gh/marcuswestin/WebViewJavascriptBridge)

An iOS/macOS bridge for sending messages between Obj-C and JavaScript in WKWebViews.

Version 8.0.0 targets iOS 15.0 and macOS 12.0 or later.

Migration Guide
---------------

-- When upgrading from v5.0.x to 6.0.x you will have to update the `setupWebViewJavascriptBridge` javascript snippet. See https://github.com/marcuswestin/WebViewJavascriptBridge#usage part 4).
-- When upgrading to 7.0.x you should support WKWebViews  only in your projects.
-- When upgrading to 8.0.0, plan for minimum deployment targets of iOS 15.0 and macOS 12.0.
-- When upgrading to 8.0.0, add the bridge user script to the application-owned configuration before creating the web view, then create the bridge before loading content. Retain the bridge for as long as it is needed.

Who uses WebViewJavascriptBridge?
---------------------------------
WebViewJavascriptBridge is used by a range of companies and projects. This is a small and incomplete sample list:

- [Facebook Messenger](https://www.facebook.com/mobile/messenger)
- [Facebook Paper](https://facebook.com/paper)
- [Yardsale](http://www.getyardsale.com/)
- [EverTrue](http://www.evertrue.com/)
- [Game Insight](http://www.game-insight.com/)
- [Sush.io](http://www.sush.io)
- [Imbed](http://imbed.github.io/)
- [CareZone](https://carezone.com)
- [Hemlig](http://www.hemlig.co)
- [Altralogica](http://www.altralogica.it)
- [鼎盛中华](https://itunes.apple.com/us/app/ding-sheng-zhong-hua/id537273940?mt=8)
- [FRIL](https://fril.jp)
- [留白·WHITE](http://liubaiapp.com)
- [BrowZine](http://thirdiron.com/browzine/)
- ... & many more!

Installation (iOS & OSX)
------------------------

### Installation with CocoaPods
Add this to your [podfile](https://guides.cocoapods.org/using/getting-started.html) and run `pod install` to install:

```ruby
pod 'WebViewJavascriptBridge', '~> 8.0'
```

The 8.0.0 pod version must be published before this dependency can be installed.

### Manual installation

Drag the `WebViewJavascriptBridge` folder into your project.

In the dialog that appears, uncheck "Copy items into destination group's folder" and select "Create groups for any folders".

Examples
--------

See the `Example Apps/` folder. Open either the iOS or OSX project and hit run to see it in action.

Run the tests with `make test`. To use an installed simulator other than the default, pass for example `DESTINATION='platform=iOS Simulator,name=iPhone 16,OS=latest'`.

### Web view configuration

Create the configuration and install the bridge script before creating the web view:

Create the bridge and register handlers before loading any content:

```objc
WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
[configuration.userContentController addUserScript:[WebViewJavascriptBridge userScript]];
WKWebView *webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
self.bridge = [WebViewJavascriptBridge bridgeForWebView:webView];
webView.navigationDelegate = self;
```

Keep a strong reference to the bridge. Install the script before creating the web view and create the bridge before the first page load. The script runs at document start. The application owns the configuration and manages `webView.navigationDelegate` directly. Each user content controller supports one active bridge and must not already use the `WebViewJavascriptBridge` message handler name. The application must prevent these conflicts; WebKit may raise an exception if the name is already registered, and the bridge does not catch it. Bridge creation returns nil and logs an error if the web view is nil or the matching script is missing.

`userScript` defaults to main-frame-only injection. Use `userScriptForMainFrameOnly:NO` to inject the script into child frames as well. This does not provide reliable frame-specific communication: native replies are evaluated in the main frame, not directed to the originating child frame. Only main-frame ready signals update the native bridge state; ordinary child-frame messages are still handled. The registered WebKit message handler can also be accessed by child frames even without injecting the bridge script there. Do not load untrusted frame content without appropriate application-level validation and restrictions on native handlers.

The first main-frame ready signal releases native calls queued during startup, but it does not guarantee that the page has registered its application handlers. Coordinate native calls with an application-level signal sent after those handlers are registered.

The compatibility target is for existing main-frame H5 pages using the documented bridge setup and JavaScript API to work without changing their page code. This is a compatibility goal, not a guarantee for every legacy page.

`setWebViewDelegate:` is no longer available; set `webView.navigationDelegate` directly. During navigation or reload, calls and responses can be lost or reach the wrong document. Each subsequent main-frame ready signal clears all native pending response callbacks without invoking them or reporting an error. Avoid relying on in-flight calls across reloads and coordinate application work with application-level readiness.

To use a WebViewJavascriptBridge in your own project:

Usage
-----

1) Import the header file and declare an ivar property:

```objc
#import "WebViewJavascriptBridge.h"
```

...

```objc
@property (nonatomic, strong) WebViewJavascriptBridge *bridge;
```

2) Install the user script, create the WKWebView, and create the bridge before loading content, as shown in Web view configuration above (iOS or macOS).

3) Register a handler in ObjC, and call a JS handler:

```objc
[self.bridge registerHandler:@"ObjC Echo" handler:^(id data, WVJBResponseCallback responseCallback) {
	NSLog(@"ObjC Echo called with: %@", data);
	responseCallback(data);
}];
[self.bridge callHandler:@"JS Echo" data:nil responseCallback:^(id responseData) {
	NSLog(@"ObjC received response: %@", responseData);
}];
```

4) Copy and paste `setupWebViewJavascriptBridge` into your JS:
	
```javascript
function setupWebViewJavascriptBridge(callback) {
	if (window.WebViewJavascriptBridge) { return callback(WebViewJavascriptBridge); }
	if (window.WVJBCallbacks) { return window.WVJBCallbacks.push(callback); }
	window.WVJBCallbacks = [callback];
	var WVJBIframe = document.createElement('iframe');
	WVJBIframe.style.display = 'none';
	WVJBIframe.src = 'https://__bridge_loaded__';
	document.documentElement.appendChild(WVJBIframe);
	setTimeout(function() { document.documentElement.removeChild(WVJBIframe) }, 0)
}
```

5) Finally, call `setupWebViewJavascriptBridge` and then use the bridge to register handlers and call ObjC handlers:

```javascript
setupWebViewJavascriptBridge(function(bridge) {
	
	/* Initialize your app here */

	bridge.registerHandler('JS Echo', function(data, responseCallback) {
		console.log("JS Echo called with:", data)
		responseCallback(data)
	})
	bridge.callHandler('ObjC Echo', {'key':'value'}, function responseCallback(responseData) {
		console.log("JS received response:", responseData)
	})
})
```

Automatic reference counting (ARC)
----------------------------------
This library relies on ARC, so if you use ARC in you project, all works fine.
But if your project have no ARC support, be sure to do next steps:

1) In your Xcode project open project settings -> 'Build Phases'

2) Expand 'Compile Sources' header and find all *.m files which are belongs to this library. Make attention on the 'Compiler Flags' in front of each source file in this list

3) For each file add '-fobjc-arc' flag

Now all WVJB files will be compiled with ARC support.

Contributors & Forks
--------------------
Contributors: https://github.com/marcuswestin/WebViewJavascriptBridge/graphs/contributors

Forks: https://github.com/marcuswestin/WebViewJavascriptBridge/network/members

API Reference
-------------

### ObjC API

##### `[WebViewJavascriptBridge userScript]`

Obtain the bridge user script and add it to the application's configuration before creating the web view.

Example:

```objc	
[configuration.userContentController addUserScript:[WebViewJavascriptBridge userScript]];
```

##### `[WebViewJavascriptBridge bridgeForWebView:(WKWebView *)webView]`

Create and retain a bridge for the web view before loading any content, after adding `[WebViewJavascriptBridge userScript]` to the configuration and creating the web view. Bridge creation returns nil if the web view or matching script is missing.

##### `[bridge registerHandler:(NSString*)handlerName handler:(WVJBHandler)handler]`

Register a handler called `handlerName`. The javascript can then call this handler with `WebViewJavascriptBridge.callHandler("handlerName")`.

Example:

```objc
[self.bridge registerHandler:@"getScreenHeight" handler:^(id data, WVJBResponseCallback responseCallback) {
	responseCallback([NSNumber numberWithInt:[UIScreen mainScreen].bounds.size.height]);
}];
[self.bridge registerHandler:@"log" handler:^(id data, WVJBResponseCallback responseCallback) {
	NSLog(@"Log: %@", data);
}];

```

##### `[bridge callHandler:(NSString*)handlerName data:(id)data]`
##### `[bridge callHandler:(NSString*)handlerName data:(id)data responseCallback:(WVJBResponseCallback)callback]`

Call the javascript handler called `handlerName`. If a `responseCallback` block is given the javascript handler can respond.

Example:

```objc
[self.bridge callHandler:@"showAlert" data:@"Hi from ObjC to JS!"];
[self.bridge callHandler:@"getCurrentPageUrl" data:nil responseCallback:^(id responseData) {
	NSLog(@"Current WKWebView page URL is: %@", responseData);
}];
```

##### `[bridge disableJavscriptAlertBoxSafetyTimeout]`

UNSAFE. Speed up bridge message passing by disabling the setTimeout safety check. It is only safe to disable this safety check if you do not call any of the javascript popup box functions (alert, confirm, and prompt). If you call any of these functions from the bridged javascript code, the app will hang.

Example:

	[self.bridge disableJavscriptAlertBoxSafetyTimeout];



### Javascript API

##### `bridge.registerHandler("handlerName", function(responseData) { ... })`

Register a handler called `handlerName`. The ObjC can then call this handler with `[bridge callHandler:"handlerName" data:@"Foo"]` and `[bridge callHandler:"handlerName" data:@"Foo" responseCallback:^(id responseData) { ... }]`

Example:

```javascript
bridge.registerHandler("showAlert", function(data) { alert(data) })
bridge.registerHandler("getCurrentPageUrl", function(data, responseCallback) {
	responseCallback(document.location.toString())
})
```


##### `bridge.callHandler("handlerName", data)`
##### `bridge.callHandler("handlerName", data, function responseCallback(responseData) { ... })`

Call an ObjC handler called `handlerName`. If a `responseCallback` function is given the ObjC handler can respond.

Example:

```javascript
bridge.callHandler("Log", "Foo")
bridge.callHandler("getScreenHeight", null, function(response) {
	alert('Screen height:' + response)
})
```


##### `bridge.disableJavscriptAlertBoxSafetyTimeout()`

Calling `bridge.disableJavscriptAlertBoxSafetyTimeout()` has the same effect as calling `[bridge disableJavscriptAlertBoxSafetyTimeout];` in ObjC.

Example:

```javascript
bridge.disableJavscriptAlertBoxSafetyTimeout()
```
