#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

static BOOL PinaTVLabInjectedEnabled = NO;
static void (*PinaTVLabOriginalSetMaximumResolution)(id, SEL, CGSize);
static id (*PinaTVLabOriginalInitWithURL)(id, SEL, NSURL *);
static id (*PinaTVLabOriginalInitWithAsset)(id, SEL, AVAsset *);
static void (*PinaTVLabOriginalAddSubview)(id, SEL, UIView *);
static void (*PinaTVLabOriginalPresentViewController)(id, SEL, UIViewController *, BOOL, void (^)(void));

static void PinaTVLabWriteLog(NSString *message) {
    NSLog(@"[PinaTVLabInjected] %@", message);
    @synchronized ([NSObject class]) {
        NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documents = paths.firstObject;
        if (documents.length == 0) return;
        NSString *path = [documents stringByAppendingPathComponent:@"PinaTVLab.log"];
        NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], message];
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!handle) {
            [[line dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:YES];
            return;
        }
        @try {
            [handle seekToEndOfFile];
            [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        } @catch (__unused NSException *exception) {
        } @finally {
            [handle closeFile];
        }
    }
}

static BOOL PinaTVLabStringLooksLikeAd(NSString *value) {
    if (![value isKindOfClass:[NSString class]] || value.length == 0) return NO;
    NSString *lower = value.lowercaseString;
    NSArray<NSString *> *tokens = @[
        @"tradplus", @"bannerad", @"banner_ad", @"adbanner", @"adview",
        @"ad_view", @"adcontainer", @"ad_container", @"splashad", @"splash_ad",
        @"interstitialad", @"interstitial_ad", @"rewardedad", @"reward_ad",
        @"rewardedad", @"nativead", @"native_ad", @"googlemobileads", @"admob",
        @"pangle", @"vungle", @"unityads", @"ksad", @"gdtad", @"adloader",
        @"ad_loader", @"admanager", @"ad_manager", @"advertisingview"
    ];
    for (NSString *token in tokens) {
        if ([lower containsString:token]) return YES;
    }
    return NO;
}

static BOOL PinaTVLabViewIdentifierLooksLikeAd(UIView *view) {
    if (!view) return NO;
    return PinaTVLabStringLooksLikeAd(NSStringFromClass(view.class)) ||
        PinaTVLabStringLooksLikeAd(view.accessibilityIdentifier) ||
        PinaTVLabStringLooksLikeAd(view.accessibilityLabel);
}

static BOOL PinaTVLabControllerLooksLikeAd(UIViewController *controller) {
    if (!controller) return NO;
    // Do not inspect the entire view tree here: an ordinary screen may contain a banner.
    return PinaTVLabStringLooksLikeAd(NSStringFromClass(controller.class)) ||
        PinaTVLabStringLooksLikeAd(controller.title) ||
        PinaTVLabStringLooksLikeAd(controller.restorationIdentifier);
}

static void PinaTVLabHookAddSubview(UIView *self, SEL selector, UIView *view) {
    if (PinaTVLabInjectedEnabled && PinaTVLabViewIdentifierLooksLikeAd(view)) {
        PinaTVLabWriteLog([NSString stringWithFormat:@"suppressed recognizable ad view: %@", NSStringFromClass(view.class)]);
        return;
    }
    if (PinaTVLabOriginalAddSubview) PinaTVLabOriginalAddSubview(self, selector, view);
}

static void PinaTVLabHookPresentViewController(UIViewController *self, SEL selector,
                                               UIViewController *viewController,
                                               BOOL animated, void (^completion)(void)) {
    if (PinaTVLabInjectedEnabled && PinaTVLabControllerLooksLikeAd(viewController)) {
        PinaTVLabWriteLog([NSString stringWithFormat:@"blocked recognizable ad modal: %@", NSStringFromClass(viewController.class)]);
        if (completion) completion();
        return;
    }
    if (PinaTVLabOriginalPresentViewController) {
        PinaTVLabOriginalPresentViewController(self, selector, viewController, animated, completion);
    }
}

static void PinaTVLabLogURL(NSURL *url) {
    if (!url) return;
    // Never write query or fragment values because media URLs may contain credentials.
    NSString *host = url.host.length ? url.host : @"<no-host>";
    NSString *path = url.path.length ? url.path : @"/";
    PinaTVLabWriteLog([NSString stringWithFormat:@"media host/path: %@%@", host, path]);
}

static void PinaTVLabHookSetMaximumResolution(id self, SEL selector, CGSize requested) {
    if (!PinaTVLabOriginalSetMaximumResolution) return;
    if (!PinaTVLabInjectedEnabled) {
        PinaTVLabOriginalSetMaximumResolution(self, selector, requested);
        return;
    }
    CGSize preferred = CGSizeMake(1920.0, 1080.0);
    if (requested.width != preferred.width || requested.height != preferred.height) {
        PinaTVLabWriteLog([NSString stringWithFormat:
            @"preferredMaximumResolution changed from %.0fx%.0f to 1920x1080",
            requested.width, requested.height]);
    }
    PinaTVLabOriginalSetMaximumResolution(self, selector, preferred);
}

static id PinaTVLabHookInitWithURL(id self, SEL selector, NSURL *url) {
    id item = PinaTVLabOriginalInitWithURL
        ? PinaTVLabOriginalInitWithURL(self, selector, url) : nil;
    if (PinaTVLabInjectedEnabled && item) {
        PinaTVLabLogURL(url);
        if (PinaTVLabOriginalSetMaximumResolution) {
            PinaTVLabOriginalSetMaximumResolution(item, @selector(setPreferredMaximumResolution:),
                                                   CGSizeMake(1920.0, 1080.0));
        }
        PinaTVLabWriteLog(@"applied 1920x1080 AVPlayerItem preference (server must supply 1080p)");
    }
    return item;
}

static id PinaTVLabHookInitWithAsset(id self, SEL selector, AVAsset *asset) {
    id item = PinaTVLabOriginalInitWithAsset
        ? PinaTVLabOriginalInitWithAsset(self, selector, asset) : nil;
    if (PinaTVLabInjectedEnabled && item) {
        if ([asset isKindOfClass:[AVURLAsset class]]) {
            PinaTVLabLogURL(((AVURLAsset *)asset).URL);
        } else {
            PinaTVLabWriteLog(@"AVPlayerItem initialized with non-URL AVAsset");
        }
        if (PinaTVLabOriginalSetMaximumResolution) {
            PinaTVLabOriginalSetMaximumResolution(item, @selector(setPreferredMaximumResolution:),
                                                   CGSizeMake(1920.0, 1080.0));
        }
        PinaTVLabWriteLog(@"applied 1920x1080 AVPlayerItem preference (server must supply 1080p)");
    }
    return item;
}

static void PinaTVLabInstallMethodHook(Class cls, SEL selector, IMP replacement, IMP *originalOut) {
    if (!cls || !selector || !replacement || !originalOut) return;
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) {
        PinaTVLabWriteLog([NSString stringWithFormat:@"method not found: %@ %@",
            NSStringFromClass(cls), NSStringFromSelector(selector)]);
        return;
    }
    *originalOut = method_setImplementation(method, replacement);
}

__attribute__((constructor))
static void PinaTVLabInjectedInitialize(void) {
    @autoreleasepool {
        NSString *bundleID = NSBundle.mainBundle.bundleIdentifier ?: @"unknown";
        if (![bundleID isEqualToString:@"com.kevin.pinatv"]) return;
        PinaTVLabInjectedEnabled = YES;

        Class itemClass = objc_getClass("AVPlayerItem");
        PinaTVLabInstallMethodHook(itemClass, @selector(setPreferredMaximumResolution:),
            (IMP)PinaTVLabHookSetMaximumResolution, (IMP *)&PinaTVLabOriginalSetMaximumResolution);
        PinaTVLabInstallMethodHook(itemClass, @selector(initWithURL:),
            (IMP)PinaTVLabHookInitWithURL, (IMP *)&PinaTVLabOriginalInitWithURL);
        PinaTVLabInstallMethodHook(itemClass, @selector(initWithAsset:),
            (IMP)PinaTVLabHookInitWithAsset, (IMP *)&PinaTVLabOriginalInitWithAsset);
        PinaTVLabInstallMethodHook(UIView.class, @selector(addSubview:),
            (IMP)PinaTVLabHookAddSubview, (IMP *)&PinaTVLabOriginalAddSubview);
        PinaTVLabInstallMethodHook(UIViewController.class,
            @selector(presentViewController:animated:completion:),
            (IMP)PinaTVLabHookPresentViewController, (IMP *)&PinaTVLabOriginalPresentViewController);

        PinaTVLabWriteLog(@"loaded; 1080p preference and recognizable ad-view/modal suppression enabled; no VIP/purchase state changed");
    }
}
