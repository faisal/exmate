#import "HOAutoScroll.h"
#import <oak/debug.h>

@interface HOAutoScroll ()
@property (nonatomic) NSRect lastFrame;
@property (nonatomic) NSRect lastVisibleRect;
@end

@implementation HOAutoScroll
- (void)scrollViewToBottom:(NSView*)aView
{
	NSRect visibleRect = [aView visibleRect];
	visibleRect.origin.y = NSHeight([aView frame]) - NSHeight(visibleRect);
	[aView scrollRectToVisible:visibleRect];
}

- (void)dealloc
{
	self.webView = nil;
}

- (NSScrollView*)scrollView
{
	return [_webView enclosingScrollView];
}

- (void)setWebView:(WKWebView*)aWebView
{
	if(aWebView == _webView)
		return;

	if(_webView = aWebView)
	{
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(webViewDidChangeFrame:) name:NSViewFrameDidChangeNotification object:nil];
		[NSNotificationCenter.defaultCenter addObserver:self selector:@selector(webViewDidChangeBounds:) name:NSViewBoundsDidChangeNotification object:nil];

		_lastFrame       = [self.scrollView.documentView frame];
		_lastVisibleRect = [self.scrollView.documentView visibleRect];
	}
	else
	{
		[NSNotificationCenter.defaultCenter removeObserver:self name:NSViewFrameDidChangeNotification object:nil];
		[NSNotificationCenter.defaultCenter removeObserver:self name:NSViewBoundsDidChangeNotification object:nil];
	}
}

- (void)webViewDidChangeBounds:(NSNotification*)aNotification
{
	NSClipView* clipView = [self.scrollView contentView];
	if(clipView != [aNotification object])
		return;

	_lastVisibleRect = [clipView.documentView visibleRect];
}

- (void)webViewDidChangeFrame:(NSNotification*)aNotification
{
	NSView* view = [aNotification object];
	if(view != self.scrollView && view != self.scrollView.documentView)
		return;

	if(view == self.scrollView.documentView)
	{
		if(NSMaxY(_lastVisibleRect) >= NSMaxY(_lastFrame))
		{
			[self scrollViewToBottom:view];
			_lastVisibleRect = [view visibleRect];
		}
		_lastFrame = [view frame];
	}

	if(view == self.scrollView)
	{
		if(NSMaxY(_lastVisibleRect) >= NSMaxY(_lastFrame))
			[self scrollViewToBottom:self.scrollView.documentView];
	}
}
@end
