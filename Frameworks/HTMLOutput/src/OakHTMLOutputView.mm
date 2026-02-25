#import "OakHTMLOutputView.h"
#import "browser/HOStatusBar.h"
#import "helpers/HOAutoScroll.h"
#import "helpers/HOJSBridge.h"
#import <OakFoundation/OakFoundation.h>
#import <OakFoundation/NSString Additions.h>
#import <OakAppKit/NSAlert Additions.h>
#import <oak/debug.h>

@interface HOStatusBar (BusyAndProgressProperties) <HOJSBridgeDelegate>
@end

@interface OakHTMLOutputView () <WKNavigationDelegate>
@property (nonatomic, getter = isRunningCommand, readwrite) BOOL runningCommand;
@property (nonatomic) HOAutoScroll* autoScrollHelper;
@property (nonatomic) std::map<std::string, std::string> environment;
@property (nonatomic) NSRect pendingVisibleRect;
@property (nonatomic, getter = isVisible) BOOL visible;
@end

@implementation OakHTMLOutputView
+ (NSSet*)keyPathsForValuesAffectingMainFrameTitle
{
	return [NSSet setWithObjects:@"webView.title", nil];
}

- (instancetype)initWithFrame:(NSRect)aRect
{
	if(self = [super initWithFrame:aRect])
	{
		_reusable = YES;
	}
	return self;
}

- (void)loadRequest:(NSURLRequest*)aRequest environment:(std::map<std::string, std::string> const&)anEnvironment autoScrolls:(BOOL)flag
{
	if(flag)
	{
		self.autoScrollHelper = [HOAutoScroll new];
		self.autoScrollHelper.webView = self.webView;
	}

	self.environment = anEnvironment;
	self.commandIdentifier = [NSURLProtocol propertyForKey:@"commandIdentifier" inRequest:aRequest];
	self.runningCommand = self.commandIdentifier != nil;

	[self willChangeValueForKey:@"mainFrameTitle"];
	[self.webView loadRequest:aRequest];
	[self didChangeValueForKey:@"mainFrameTitle"];
}

- (void)stopLoadingWithUserInteraction:(BOOL)askUserFlag completionHandler:(void(^)(BOOL didStop))handler
{
	WKBackForwardListItem* currentItem = self.webView.backForwardList.currentItem;
	NSURLRequest* request = currentItem ? [NSURLRequest requestWithURL:currentItem.URL] : nil;
	id command = request ? [NSURLProtocol propertyForKey:@"command" inRequest:request] : nil;
	if(command)
	{
		NSAlert* alert = nil;
		if(askUserFlag)
		{
			NSString* processName = [NSURLProtocol propertyForKey:@"processName" inRequest:request];
			alert = [NSAlert tmAlertWithMessageText:[NSString stringWithFormat:@"Stop \"%@\"?", processName] informativeText:@"The job that the task is performing will not be completed." buttons:@"Stop", @"Cancel", nil];
		}

		__weak __block id token = [NSNotificationCenter.defaultCenter addObserverForName:@"OakCommandDidTerminateNotification" object:command queue:nil usingBlock:^(NSNotification* notification){
			if(alert)
				[self.window endSheet:alert.window returnCode:NSAlertFirstButtonReturn];
			handler(YES);
			[NSNotificationCenter.defaultCenter removeObserver:token];
		}];

		if(alert)
		{
			[alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode){
				if(returnCode == NSAlertFirstButtonReturn) /* "Stop" */
				{
					[self.webView stopLoading];
				}
				else
				{
					handler(NO);
					[NSNotificationCenter.defaultCenter removeObserver:token];
				}
			}];
		}
		else
		{
			[self.webView stopLoading];
		}
	}
	else
	{
		handler(YES);
	}
}

- (void)setContent:(NSString*)someHTML
{
	self.pendingVisibleRect = [self.webView enclosingScrollView].documentView.visibleRect;
	[self.webView loadHTMLString:someHTML baseURL:[NSURL fileURLWithPath:NSHomeDirectory()]];
}

- (NSString*)mainFrameTitle
{
	if(OakIsEmptyString(self.webView.title))
	{
		NSURL* url = self.webView.backForwardList.currentItem.URL;
		if(NSURLRequest* request = url ? [NSURLRequest requestWithURL:url] : nil)
			return [NSURLProtocol propertyForKey:@"processName" inRequest:request] ?: @"";
	}
	return self.webView.title;
}

- (void)viewDidMoveToWindow
{
	[NSNotificationCenter.defaultCenter removeObserver:self name:NSWindowWillCloseNotification object:nil];
	if(self.window)
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(windowWillClose:) name:NSWindowWillCloseNotification object:self.window];
	self.visible = self.window ? YES : NO;
}

- (void)windowWillClose:(NSNotification*)aNotification
{
	self.visible = NO;
}

// ===========================
// = WKNavigationDelegate =
// ===========================

- (void)webView:(WKWebView*)webView didStartProvisionalNavigation:(WKNavigation*)navigation
{
	self.statusBar.busy = YES;
	[self setUpdatesProgress:!self.isRunningCommand];
}

- (void)webView:(WKWebView*)webView didFinishNavigation:(WKNavigation*)navigation
{
	self.runningCommand = NO;
	self.autoScrollHelper = nil;

	if(!NSIsEmptyRect(self.pendingVisibleRect))
		[[self.webView enclosingScrollView].documentView scrollRectToVisible:self.pendingVisibleRect];
	self.pendingVisibleRect = NSZeroRect;
}

- (void)webView:(WKWebView*)webView didFailProvisionalNavigation:(WKNavigation*)navigation withError:(NSError*)error
{
	self.runningCommand = NO;
	self.autoScrollHelper = nil;
}

- (void)webView:(WKWebView*)webView didFailNavigation:(WKNavigation*)navigation withError:(NSError*)error
{
	self.runningCommand = NO;
	self.autoScrollHelper = nil;
}

- (void)webView:(WKWebView*)webView decidePolicyForNavigationAction:(WKNavigationAction*)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
	NSURLRequest* request = navigationAction.request;
	if([NSURLConnection canHandleRequest:request])
	{
		decisionHandler(WKNavigationActionPolicyAllow);
	}
	else
	{
		decisionHandler(WKNavigationActionPolicyCancel);
		NSURL* url = request.URL;
		if([[url scheme] isEqualToString:@"txmt"])
		{
			auto projectUUID = _environment.find("TM_PROJECT_UUID");
			if(projectUUID != _environment.end())
				url = [NSURL URLWithString:[[url absoluteString] stringByAppendingFormat:@"&project=%@", [NSString stringWithCxxString:projectUUID->second]]];
			[NSApp sendAction:@selector(handleTxMtURL:) to:nil from:url];
		}
		else
		{
			[NSWorkspace.sharedWorkspace openURL:url];
		}
	}
}

// ====================
// = Printing Support =
// ====================

- (IBAction)printDocument:(id)sender
{
	NSPrintOperation* printer = [NSPrintOperation printOperationWithView:[self.webView enclosingScrollView].documentView];
	[[printer printPanel] setOptions:[[printer printPanel] options] | NSPrintPanelShowsPaperSize | NSPrintPanelShowsOrientation];

	NSPrintInfo* info = [printer printInfo];

	NSRect display = NSIntersectionRect(info.imageablePageBounds, (NSRect){ NSZeroPoint, info.paperSize });
	info.leftMargin   = NSMinX(display);
	info.rightMargin  = info.paperSize.width - NSMaxX(display);
	info.topMargin    = info.paperSize.height - NSMaxY(display);
	info.bottomMargin = NSMinY(display);

	[printer runOperationModalForWindow:self.window delegate:nil didRunSelector:NULL contextInfo:nil];
}
@end
