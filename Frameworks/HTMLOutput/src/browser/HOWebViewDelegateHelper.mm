#import "HOWebViewDelegateHelper.h"
#import "HOBrowserView.h"
#import <OakAppKit/NSAlert Additions.h>
#import <OakFoundation/NSString Additions.h>
#import <io/path.h>
#import <oak/debug.h>

static NSString* const kUserDefaultsDefaultURLProtocolKey = @"defaultURLProtocol";

static BOOL IsProtocolRelativeURL (NSURL* url)
{
	if([url.scheme hasPrefix:@"x-txmt"] && ![url.host isEqualToString:@"job"])
		return YES;

	if([url.scheme isEqualToString:@"file"] && url.host)
	{
		if([url.host containsString:@"."] && ![NSFileManager.defaultManager fileExistsAtPath:[@"/" stringByAppendingPathComponent:url.host]])
			return YES;
	}

	return NO;
}

@implementation HOWebViewDelegateHelper
+ (void)initialize
{
	[NSUserDefaults.standardUserDefaults registerDefaults:@{
		kUserDefaultsDefaultURLProtocolKey: @"https",
	}];
}

// ===================
// = WKUIDelegate =
// ===================

- (void)webView:(WKWebView*)webView decidePolicyForNavigationAction:(WKNavigationAction*)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
	NSURLRequest* request = navigationAction.request;
	if([[[request URL] scheme] isEqualToString:@"tm-file"])
	{
		NSString* fragment = [[request URL] fragment];
		request = [NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"file://localhost%@%s%@", [[[request URL] path] stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet], fragment ? "#" : "", fragment ?: @""]]];
	}

	if(IsProtocolRelativeURL([request URL]))
	{
		NSURLComponents* components = [NSURLComponents componentsWithURL:[request URL] resolvingAgainstBaseURL:YES];
		components.scheme = [NSUserDefaults.standardUserDefaults stringForKey:kUserDefaultsDefaultURLProtocolKey];
		request = [NSURLRequest requestWithURL:components.URL];
	}

	if([[request URL] isFileURL])
	{
		NSURL* redirectURL = [NSURL URLWithString:[NSString stringWithFormat:@"file://localhost%@?path=%@&error=1", [[[NSBundle bundleForClass:[self class]] pathForResource:@"error_not_found" ofType:@"html"] stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet], [[[request URL] path] stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet]]];
		char const* path = [[request URL] fileSystemRepresentation];

		struct stat buf;
		if(path && stat(path, &buf) == 0)
		{
			if(S_ISREG(buf.st_mode) || S_ISLNK(buf.st_mode))
			{
				redirectURL = nil;
			}
			else if(S_ISDIR(buf.st_mode))
			{
				if(path::exists(path::join(path, "index.html")))
				{
					NSString* urlString = [[NSURL URLWithString:@"index.html" relativeToURL:[request URL]] absoluteString];
					if(NSString* query = [[request URL] query])
						urlString = [urlString stringByAppendingFormat:@"?%@", query];
					if(NSString* fragment = [[request URL] fragment])
						urlString = [urlString stringByAppendingFormat:@"#%@", fragment];
					redirectURL = [NSURL URLWithString:urlString];
				}
			}
		}

		if(redirectURL)
			request = [NSURLRequest requestWithURL:redirectURL];
	}

	decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView*)webView runJavaScriptAlertPanelWithMessage:(NSString*)message initiatedByFrame:(WKFrameInfo*)frame completionHandler:(void (^)(void))completionHandler
{
	NSAlert* alert = [NSAlert tmAlertWithMessageText:NSLocalizedString(@"Script Message", @"JavaScript alert title") informativeText:message buttons:NSLocalizedString(@"OK", @"JavaScript alert confirmation"), nil];
	[alert beginSheetModalForWindow:[webView window] completionHandler:^(NSModalResponse returnCode) {
		completionHandler();
	}];
}

- (void)webView:(WKWebView*)webView runJavaScriptConfirmPanelWithMessage:(NSString*)message initiatedByFrame:(WKFrameInfo*)frame completionHandler:(void (^)(BOOL))completionHandler
{
	NSAlert* alert        = [[NSAlert alloc] init];
	alert.messageText     = NSLocalizedString(@"Script Message", @"JavaScript alert title");
	alert.informativeText = message;
	[alert addButtons:NSLocalizedString(@"OK", @"JavaScript alert confirmation"), NSLocalizedString(@"Cancel", @"JavaScript alert cancel"), nil];
	[alert beginSheetModalForWindow:[webView window] completionHandler:^(NSModalResponse returnCode) {
		completionHandler(returnCode == NSAlertFirstButtonReturn);
	}];
}

- (void)webView:(WKWebView*)webView runOpenPanelWithParameters:(WKOpenPanelParameters*)parameters initiatedByFrame:(WKFrameInfo*)frame completionHandler:(void (^)(NSArray<NSURL *> * _Nullable))completionHandler
{
	NSOpenPanel* panel = [NSOpenPanel openPanel];
	panel.allowsMultipleSelection = parameters.allowsMultipleSelection;
	[panel setDirectoryURL:[NSURL fileURLWithPath:NSHomeDirectory()]];
	if([panel runModal] == NSModalResponseOK)
		completionHandler(panel.URLs);
	else
		completionHandler(nil);
}

- (WKWebViewConfiguration *)webView:(WKWebView *)webView createWebViewConfigurationForNavigationAction:(WKNavigationAction *)navigationAction
{
	WKWebViewConfiguration* config = [[WKWebViewConfiguration alloc] init];
	config.preferences.javaScriptCanOpenWindowsAutomatically = NO;
	return config;
}

- (void)webViewDidClose:(WKWebView *)webView
{
	if(![webView tryToPerform:@selector(toggleHTMLOutput:) with:self])
		[webView tryToPerform:@selector(performClose:) with:self];
	self.needsNewWebView = YES;
}

- (void)webView:(WKWebView*)webView didReceiveServerRedirectForProvisionalNavigation:(WKNavigation*)navigation
{
}
@end

@interface HTMLTMFileDummyProtocol : NSURLProtocol { }
@end

@implementation HTMLTMFileDummyProtocol
+ (void)load                                                                                                                                      { [self registerClass:self]; }
+ (BOOL)canInitWithRequest:(NSURLRequest*)request                                                                                                 { return [[[request URL] scheme] isEqualToString:@"tm-file"]; }
+ (NSURLRequest*)canonicalRequestForRequest:(NSURLRequest*)request                                                                                { return request; }
+ (BOOL)requestIsCacheEquivalent:(NSURLRequest*)a toRequest:(NSURLRequest*)b                                                                      { return NO; }
@end
