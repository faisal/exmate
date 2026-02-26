// Obj-C++ helper for opening URLs using NSWorkspace (replacement for deprecated LSOpenURLsWithRole)
#import <AppKit/AppKit.h>
#import <CoreServices/CoreServices.h>

extern "C" void path_open_urls(CFArrayRef urls)
{
    if(!urls)
        return;

    NSArray *nsURLs = (__bridge NSArray *)urls;
    for(NSURL *u in nsURLs)
    {
        [[NSWorkspace sharedWorkspace] openURL:u];
    }
    return;
}
