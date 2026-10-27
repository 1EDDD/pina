#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <stdlib.h>

static BOOL PinaTVLabEnabled = YES;
static NSMutableSet<NSString *> *PinaTVLabLoggedClasses;

static void PinaTVLabLog(NSString *message) {
    NSLog(@"[PinaTVLabTweak] %@", message);
}

static BOOL PinaTVLabContainsAny(NSString *value, NSArray<NSString *> *needles) {
    NSString *lower = value.lowercaseString;
    for (NSString *needle in needles) {
        if ([lower containsString:needle]) return YES;
    }
    return NO;
}

static NSArray<NSString *> *PinaTVLabRuntimeClassNeedles(void) {
    return @[@"vipservice", @"tradplusadservice", @"splashadhandler",
             @"resolutionselector", @"resolutionoption", @"videoservice",
             @"adservice", @"bannerad", @"rewardad", @"interstitialad",
             @"googlemobileads", @"pangle", @"vungle", @"unityads"];
}

static NSArray<NSString *> *PinaTVLabSelectorNeedles(void) {
    return @[@"vip", @"purchase", @"purchaser", @"resolution", @"quality",
             @"playback", @"selected", @"startresolution", @"lockplayback",
             @"present", @"showad", @"loadad", @"reward", @"interstitial",
             @"banner", @"splash", @"tradplus", @"googlemobileads"];
}

/// Diagnostic-only: print Objective-C-visible selectors for relevant loaded classes.
/// Pure Swift symbols that are not exposed to the Objective-C runtime will not appear.
static void PinaTVLabLogSelectorsForClass(Class cls, BOOL classMethods) {
    unsigned int count = 0;
    Class target = classMethods ? object_getClass(cls) : cls;
    Method *methods = class_copyMethodList(target, &count);
    NSMutableArray<NSString *> *matches = [NSMutableArray array];
    NSArray<NSString *> *needles = PinaTVLabSelectorNeedles();

    for (unsigned int i = 0; i < count; i++) {
        SEL selector = method_getName(methods[i]);
        const char *rawName = sel_getName(selector);
        if (!rawName) continue;
        NSString *name = [NSString stringWithUTF8String:rawName];
        if (PinaTVLabContainsAny(name, needles)) {
            [matches addObject:name];
        }
    }
    free(methods);

    if (matches.count > 0) {
        NSString *kind = classMethods ? @"class" : @"instance";
        PinaTVLabLog([NSString stringWithFormat:@"%@ selectors for %@: %@",
            kind, NSStringFromClass(cls), [matches componentsJoinedByString:@", "]]);
    }
}

static void PinaTVLabScanRuntimeClasses(void) {
    int count = objc_getClassList(NULL, 0);
    if (count <= 0) return;

    Class *classes = (Class *)calloc((size_t)count, sizeof(Class));
    if (!classes) return;
    int actual = objc_getClassList(classes, count);
    NSArray<NSString *> *needles = PinaTVLabRuntimeClassNeedles();

    for (int i = 0; i < actual; i++) {
        Class cls = classes[i];
        NSString *name = NSStringFromClass(cls);
        if (!name || !PinaTVLabContainsAny(name, needles)) continue;

        @synchronized (PinaTVLabLoggedClasses) {
            if ([PinaTVLabLoggedClasses containsObject:name]) continue;
            [PinaTVLabLoggedClasses addObject:name];
        }

        PinaTVLabLog([NSString stringWithFormat:@"Relevant runtime class loaded: %@", name]);
        PinaTVLabLogSelectorsForClass(cls, NO);
        PinaTVLabLogSelectorsForClass(cls, YES);
    }
    free(classes);
}

/// Preference only. AVPlayer cannot select a rendition that the media source does not offer.
%hook AVPlayerItem

- (void)setPreferredMaximumResolution:(CGSize)resolution {
    if (PinaTVLabEnabled) {
        CGSize preferred = CGSizeMake(1920.0, 1080.0);
        PinaTVLabLog([NSString stringWithFormat:
            @"AVPlayerItem max-resolution request %.0fx%.0f; preferring 1920x1080",
            resolution.width, resolution.height]);
        %orig(preferred);
        return;
    }
    %orig(resolution);
}

%end

/// Logs likely ad views. This does not remove views or block ad SDK requests.
static void PinaTVLabLogRelevantViews(UIView *view) {
    if (!view) return;
    NSString *className = NSStringFromClass([view class]);
    NSArray<NSString *> *needles = @[@"tradplus", @"splashad", @"bannerad",
        @"rewardad", @"interstitialad", @"googlemobileads", @"pangle",
        @"vungle", @"unityads"];
    if (PinaTVLabContainsAny(className, needles)) {
        PinaTVLabLog([NSString stringWithFormat:@"Observed ad-related view class: %@", className]);
    }
    for (UIView *child in view.subviews) {
        PinaTVLabLogRelevantViews(child);
    }
}

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (PinaTVLabEnabled) {
        PinaTVLabScanRuntimeClasses();
        PinaTVLabLogRelevantViews(self.view);
    }
}

- (void)presentViewController:(UIViewController *)viewController
                     animated:(BOOL)animated
                   completion:(void (^)(void))completion {
    if (PinaTVLabEnabled && viewController) {
        PinaTVLabLog([NSString stringWithFormat:@"Modal presentation: presenter=%@ presented=%@",
            NSStringFromClass([self class]), NSStringFromClass([viewController class])]);
    }
    %orig(viewController, animated, completion);
}

%end

%ctor {
    @autoreleasepool {
        NSString *bundleID = NSBundle.mainBundle.bundleIdentifier ?: @"unknown";
        if (![bundleID isEqualToString:@"com.kevin.pinatv"]) {
            PinaTVLabEnabled = NO;
            return;
        }
        PinaTVLabLoggedClasses = [NSMutableSet set];
        PinaTVLabLog(@"Loaded for PinaTV. 1080p preference and runtime diagnostics enabled; no ad/VIP checks are modified.");
    }
}
