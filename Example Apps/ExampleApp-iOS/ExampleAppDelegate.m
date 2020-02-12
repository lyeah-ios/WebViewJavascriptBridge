#import "ExampleAppDelegate.h"
#import "ExampleWKWebViewController.h"

@implementation ExampleAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
    // 1. Create the WKWebView example
    ExampleWKWebViewController* WKWebViewExampleController = [[ExampleWKWebViewController alloc] init];
    WKWebViewExampleController.tabBarItem.title             = @"WKWebView";

    // 2. Create the tab footer and add the WKWebView example
    UITabBarController *tabBarController = [[UITabBarController alloc] init];
    [tabBarController addChildViewController:WKWebViewExampleController];

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.rootViewController = tabBarController;
    [self.window makeKeyAndVisible];
    return YES;
}

@end
