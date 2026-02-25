#import "HOBrowserView.h"
#import "HOWebViewDelegateHelper.h"
#import "HOStatusBar.h"
#import "../helpers/HOJSBridge.h"
#import <OakAppKit/OakUIConstructionFunctions.h>

static NSString* EscapeHTML (NSString* str)
{
	return [[[str stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"] stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"] stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
}

static void ShowLoadErrorForURL (WKWebView* webView, NSURL* url, NSError* error)
{
	NSString* options  = [[url scheme] isEqualToString:@"file"] ? @" -R" : @"";
	NSString* errorMsg = [NSString stringWithFormat:@"<title>Load Error</title><h1>Load Error</h1><p>WebKit reported <em>%@</em> while loading <tt><a href=\"#\" onClick=\"javascript:TextMate.system('/usr/bin/open%@ &quot;%@&quot;', null)\">%@</a></tt>.</p>", EscapeHTML([error localizedDescription]), options, EscapeHTML([url absoluteString]), EscapeHTML([url absoluteString])];
	[webView loadHTMLString:errorMsg baseURL:[NSURL fileURLWithPath:NSTemporaryDirectory()]];
}

@interface HOBrowserView () <WKUIDelegate>
@property (nonatomic, readwrite) WKWebView* webView;
@property (nonatomic, readwrite) HOStatusBar* statusBar;
@property (nonatomic) HOWebViewDelegateHelper* webViewDelegateHelper;
@end

@implementation HOBrowserView
- (id)initWithFrame:(NSRect)frame
{
	if(self = [super initWithFrame:frame])
	{
		HOJSBridge* jsBridge = [HOJSBridge new];
		[jsBridge setDelegate:_statusBar];

		WKWebViewConfiguration* webConfig = [[WKWebViewConfiguration alloc] init];
		webConfig.preferences.javaScriptCanOpenWindowsAutomatically = NO;
		[webConfig.userContentController addScriptMessageHandler:jsBridge name:@"textmate"];

		WKUserScript* script = [[WKUserScript alloc] initWithSource:[HOJSBridge javaScriptBridge] injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES];
		[webConfig.userContentController addUserScript:script];

		_webView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:webConfig];

		_statusBar = [[HOStatusBar alloc] initWithFrame:NSZeroRect];
		_statusBar.delegate = _webView;

		_webViewDelegateHelper          = [HOWebViewDelegateHelper new];
		_webViewDelegateHelper.delegate = _statusBar;
		_webView.navigationDelegate     = self;
		_webView.UIDelegate            = _webViewDelegateHelper;

		NSDictionary* views = @{
			@"webView":   _webView,
			@"statusBar": _statusBar
		};

		OakAddAutoLayoutViewsToSuperview([views allValues], self);

		[self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[webView(>=10)]|"            options:0                                                      metrics:nil views:views]];
		[self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[webView(>=10)][statusBar]|" options:NSLayoutFormatAlignAllLeft|NSLayoutFormatAlignAllRight metrics:nil views:views]];
	}
	return self;
}

- (BOOL)needsNewWebView
{
	return _webViewDelegateHelper.needsNewWebView;
}

- (void)webViewProgressEstimateChanged:(NSNotification*)notification
{
	_statusBar.progress = _webView.estimatedProgress;
}

- (void)dealloc
{
	[self setUpdatesProgress:NO];
	_webView.navigationDelegate = nil;
	_webView.UIDelegate        = nil;
	[_webView stopLoading];
}

- (void)setUpdatesProgress:(BOOL)flag
{
	if(flag)
	{
		[_webView addObserver:self forKeyPath:@"estimatedProgress" options:NSKeyValueObservingOptionNew context:nil];
	}
	else
	{
		[_webView removeObserver:self forKeyPath:@"estimatedProgress"];
	}
}

- (void)observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id>*)change context:(void*)context
{
	if([keyPath isEqualToString:@"estimatedProgress"])
	{
		_statusBar.progress = _webView.estimatedProgress;
	}
}

// ==============
// = Key Events =
// ==============

/*
Since the webView is typically the first responder, the path for key events is as follows:

For keyDown:
	webView
	HOBrowserView
	OakHTMLOutputView
	NSWindow

For performKeyEquivalent:
	NSWindow
	OakHTMLOutputView
	HOBrowserView
	webView

A webView default implementation passes all key events, including potential key equivalents (except ESC),
to the webpage so that it may have a chance to respond. Unfortunately, we cannot know if these events are
handled so the events are still forwarded down their respective chains as shown above. So to avoid the
NSBeep when hitting the end of the responder chain, we let HOBrowserView swallow all key events. This is
safe since performKeyEquivalent: is called first, which leads to another problem: we can pass
the key event back to the webView (minus the modifier). Therefore, we also terminate the above chain for
performKeyEquivalent: by overriding the method here and returning just NO. Note: that if none of the views
in the hierachy returns YES, the key (equivalent) event is then passed to the menus.
*/

- (BOOL)performKeyEquivalent
{
	return NO;
}

- (void)keyDown:(NSEvent*)anEvent
{

}

// =========
// = Swipe =
// =========

- (BOOL)wantsScrollEventsForSwipeTrackingOnAxis:(NSEventGestureAxis)axis
{
	return axis == NSEventGestureAxisHorizontal;
}

- (void)scrollWheel:(NSEvent*)anEvent
{
	if(![NSEvent isSwipeTrackingFromScrollEventsEnabled] || [anEvent phase] == NSEventPhaseNone || fabs([anEvent scrollingDeltaX]) <= fabs([anEvent scrollingDeltaY]))
		return;

	[anEvent trackSwipeEventWithOptions:0 dampenAmountThresholdMin:(_webView.canGoForward ? -1 : 0) max:(_webView.canGoBack ? +1 : 0) usingHandler:^(CGFloat gestureAmount, NSEventPhase phase, BOOL isComplete, BOOL* stop) {
		if(phase == NSEventPhaseBegan)
		{
			// Setup animation overlay layers
		}

		// Update animation overlay to match gestureAmount

		if(phase == NSEventPhaseEnded)
		{
			if(gestureAmount > 0 && _webView.canGoBack)
				[_webView goBack];
			else if(gestureAmount < 0 && _webView.canGoForward)
				[_webView goForward];
		}

		if(isComplete)
		{
			// Tear down animation overlay here
		}
	}];
}

// ===========================
// = WKNavigationDelegate =
// ===========================

- (void)webView:(WKWebView*)webView didStartProvisionalNavigation:(WKNavigation*)navigation
{
	_statusBar.busy = YES;
	[self setUpdatesProgress:YES];
}

- (void)webView:(WKWebView*)webView didFailProvisionalNavigation:(WKNavigation*)navigation withError:(NSError*)error
{
	ShowLoadErrorForURL(webView, webView.URL, error);
	_statusBar.canGoBack    = webView.canGoBack;
	_statusBar.canGoForward = webView.canGoForward;
	_statusBar.busy         = NO;
	_statusBar.progress     = 0;
}

- (void)webView:(WKWebView*)webView didFailNavigation:(WKNavigation*)navigation withError:(NSError*)error
{
	ShowLoadErrorForURL(webView, webView.URL, error);
	_statusBar.canGoBack    = webView.canGoBack;
	_statusBar.canGoForward = webView.canGoForward;
	_statusBar.busy         = NO;
	_statusBar.progress     = 0;
}

- (void)webView:(WKWebView*)webView didFinishNavigation:(WKNavigation*)navigation
{
	_statusBar.canGoBack    = webView.canGoBack;
	_statusBar.canGoForward = webView.canGoForward;
	_statusBar.busy         = NO;
	_statusBar.progress     = 0;
}
@end
