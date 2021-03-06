/* vi:set ts=8 sts=4 sw=4 noet:
 *
 * VIM - Vi IMproved		by Bram Moolenaar
 *
 * Do ":help uganda"  in Vim to read copying and usage conditions.
 * Do ":help credits" in Vim to see a list of people who contributed.
 * See README.txt for an overview of the Vim source code.
 */

/*
 * os_macosx.m -- Mac specific things for Mac OS X.
 */

/* Suppress compiler warnings to non-C89 code. */
#if defined(__clang__) && defined(__STRICT_ANSI__)
# pragma clang diagnostic push
# pragma clang diagnostic ignored "-Wc99-extensions"
# pragma clang diagnostic push
# pragma clang diagnostic ignored "-Wdeclaration-after-statement"
#endif

/* Avoid a conflict for the definition of Boolean between Mac header files and
 * X11 header files. */
#define NO_X11_INCLUDES

#include "vim.h"
#import <AppKit/AppKit.h>


/*
 * Clipboard support for the console.
 * Don't include this when building the GUI version, the functions in
 * gui_mac.c are used then.  TODO: remove those instead?
 * But for MacVim we do need these ones.
 */
#if defined(FEAT_CLIPBOARD)

/* Used to identify clipboard data copied from Vim. */

NSString *VimPboardType = @"VimPboardType";

    void
clip_mch_lose_selection(Clipboard_T *cbd UNUSED)
{
}


    int
clip_mch_own_selection(Clipboard_T *cbd UNUSED)
{
    /* This is called whenever there is a new selection and 'guioptions'
     * contains the "a" flag (automatically copy selection).  Return TRUE, else
     * the "a" flag does nothing.  Note that there is no concept of "ownership"
     * of the clipboard in Mac OS X.
     */
    return TRUE;
}


    void
clip_mch_request_selection(Clipboard_T *cbd)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    NSPasteboard *pb = [NSPasteboard generalPasteboard];
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 1060
    NSArray *supportedTypes = [NSArray arrayWithObjects:VimPboardType,
	    NSPasteboardTypeString, nil];
#else
    NSArray *supportedTypes = [NSArray arrayWithObjects:VimPboardType,
	    NSStringPboardType, nil];
#endif
    NSString *bestType = [pb availableTypeFromArray:supportedTypes];
    if (!bestType) goto releasepool;

    int motion_type = MAUTO;
    NSString *string = nil;

    if ([bestType isEqual:VimPboardType])
    {
	/* This type should consist of an array with two objects:
	 *   1. motion type (NSNumber)
	 *   2. text (NSString)
	 * If this is not the case we fall back on using NSPasteboardTypeString.
	 */
	id plist = [pb propertyListForType:VimPboardType];
	if ([plist isKindOfClass:[NSArray class]] && [plist count] == 2)
	{
	    id obj = [plist objectAtIndex:1];
	    if ([obj isKindOfClass:[NSString class]])
	    {
		motion_type = [[plist objectAtIndex:0] intValue];
		string = obj;
	    }
	}
    }

    if (!string)
    {
	/* Use NSPasteboardTypeString.  The motion type is detected automatically.
	 */
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 1060
	NSMutableString *mstring =
		[[pb stringForType:NSPasteboardTypeString] mutableCopy];
#else
	NSMutableString *mstring =
		[[pb stringForType:NSStringPboardType] mutableCopy];
#endif
	if (!mstring) goto releasepool;

	/* Replace unrecognized end-of-line sequences with \x0a (line feed). */
	NSRange range = { 0, [mstring length] };
	unsigned n = [mstring replaceOccurrencesOfString:@"\x0d\x0a"
					     withString:@"\x0a" options:0
						  range:range];
	if (0 == n)
	{
	    n = [mstring replaceOccurrencesOfString:@"\x0d" withString:@"\x0a"
					   options:0 range:range];
	}

	string = mstring;
    }

    /* Default to MAUTO, uses MCHAR or MLINE depending on trailing NL. */
    if (!(MCHAR == motion_type || MLINE == motion_type || MBLOCK == motion_type
	    || MAUTO == motion_type))
	motion_type = MAUTO;

    char_u *str = (char_u*)[string UTF8String];
    int len = [string lengthOfBytesUsingEncoding:NSUTF8StringEncoding];

    if (input_conv.vc_type != CONV_NONE)
	str = string_convert(&input_conv, str, &len);

    if (str)
	clip_yank_selection(motion_type, str, len, cbd);

    if (input_conv.vc_type != CONV_NONE)
	vim_free(str);

releasepool:
    [pool release];
}


/*
 * Send the current selection to the clipboard.
 */
    void
clip_mch_set_selection(Clipboard_T *cbd)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    /* If the '*' register isn't already filled in, fill it in now. */
    cbd->owned = TRUE;
    clip_get_selection(cbd);
    cbd->owned = FALSE;

    /* Get the text to put on the pasteboard. */
    long_u llen = 0; char_u *str = 0;
    int motion_type = clip_convert_selection(&str, &llen, cbd);
    if (motion_type < 0)
	goto releasepool;

    /* TODO: Avoid overflow. */
    int len = (int)llen;
    if (output_conv.vc_type != CONV_NONE)
    {
	char_u *conv_str = string_convert(&output_conv, str, &len);
	if (conv_str)
	{
	    vim_free(str);
	    str = conv_str;
	}
    }

    if (len > 0)
    {
	NSString *string = [[NSString alloc]
	    initWithBytes:str length:len encoding:NSUTF8StringEncoding];

	/* See clip_mch_request_selection() for info on pasteboard types. */
	NSPasteboard *pb = [NSPasteboard generalPasteboard];
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 1060
	NSArray *supportedTypes = [NSArray arrayWithObjects:VimPboardType,
		NSPasteboardTypeString, nil];
#else
	NSArray *supportedTypes = [NSArray arrayWithObjects:VimPboardType,
		NSStringPboardType, nil];
#endif
	[pb declareTypes:supportedTypes owner:nil];

	NSNumber *motion = [NSNumber numberWithInt:motion_type];
	NSArray *plist = [NSArray arrayWithObjects:motion, string, nil];
	[pb setPropertyList:plist forType:VimPboardType];

#if MAC_OS_X_VERSION_MAX_ALLOWED >= 1060
	[pb setString:string forType:NSPasteboardTypeString];
#else
	[pb setString:string forType:NSStringPboardType];
#endif

	[string release];
    }

    vim_free(str);
releasepool:
    [pool release];
}

#endif /* FEAT_CLIPBOARD */

/* Lift the compiler warning suppression. */
#if defined(__clang__) && defined(__STRICT_ANSI__)
# pragma clang diagnostic pop
# pragma clang diagnostic pop
#endif

    void
macosx_fork()
{
    pid_t pid;
    int   i;

    /*
     * On OS X, you have to exec after a fork, otherwise calls to frameworks
     * will assert (and without Core Foundation, you can't start the gui. What
     * fun.). See CAVEATS at:
     *
     *	 http://developer.apple.com/documentation/Darwin/Reference/ManPages/
     *							    man2/fork.2.html
     *
     * Since we have to go through this anyways, we might as well use vfork.
     * But: then we can't detach from our starting shell, so stick with fork.
     */

    /* Stolen from http://paste.lisp.org/display/50906 */
    extern int *_NSGetArgc(void);
    extern char ***_NSGetArgv(void);

    int argc = *_NSGetArgc();
    char ** argv = *_NSGetArgv();
    char * newargv[argc+2];

    newargv[0] = argv[0];

    /*
     * Make sure "-f" is in front of potential "--remote" flags, else
     * they would consume it.
     */
    newargv[1] = "-f";

    for (i = 1; i < argc; i++) {
	newargv[i + 1] = argv[i];
    }
    newargv[argc+1] = NULL;

    pid = fork();
    switch(pid) {
	case -1:
#ifndef NDEBUG
	    fprintf(stderr, "vim: Mac OS X workaround fork() failed!");
#endif
	    _exit(255);
	case 0:
	    /* Child. */

	    /* Make sure we survive our shell */
	    setsid();

	    /* Restarts the vim process, will not return. */
	    execvp(argv[0], newargv);

	    /* If we come here, exec has failed. bail. */
	    _exit(255);
	default:
	    /* Parent */
	    _exit(0);
    }
}
