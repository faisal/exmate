#import <WebKit/WebKit.h>
#import <oak/misc.h>

@class HOStatusBar;

@interface HOBrowserView : NSView <WKNavigationDelegate>
@property (nonatomic, readonly) WKWebView* webView;
@property (nonatomic, readonly) BOOL needsNewWebView;
@property (nonatomic, readonly) HOStatusBar* statusBar;
- (void)setUpdatesProgress:(BOOL)flag;
@end
