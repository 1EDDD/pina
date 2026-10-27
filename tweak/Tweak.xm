#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static BOOL PinaTVLabEnabled = YES;
static void PinaTVLabLog(NSString *message) {
    NSLog(@"[PinaTVLabTweak] %@", message);
}

/// This is an experimental preference hook, not a VIP bypass.
/// AVPlayer can only play a 1080p rendition if the source provides one.
%hook AVPlayerItem

- (void)setPreferredMaximumResolution:(CGSize)resolution {
    if (PinaTVLabEnabled) {
        CGSize preferred = CGSizeMake(1920.0, 1080.0);
        PinaTVLabLog([NSString stringWithFormat:
            @"Requested maximum resolution %.0fx%.0f; setting preference to 1920x1080",
            resolution.width, resolution.height]);
        %orig(preferred);
        return;
    }
    %orig(resolution);
}

%end

/// Diagnostic-only view scan. It does not remove views or block ad SDK calls.
/// Runtime class names help identify the exact ad presentation path before implementing
/// a narrowly scoped, authorized change in the app's source/build configuration.
static void PinaTVLabLogRelevantViews(UIView *view) {
    if (!view) return;
    NSString *className = NSStringFromClass([view class]);
    NSString *lower = className.lowercaseString;
    if ([lower containsString:@"tradplus"] ||
        [lower containsString:@"splashad"] ||
        [lower containsString:@"bannerad"] ||
        [lower containsString:@"rewardad"] ||
        [lower containsString:@"googlemobileads"] ||
        [lower containsString:@"pangle"] ||
        [lower containsString:@"vungle"] ||
        [lower containsString:@"unityads"]) {
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
        PinaTVLabLogRelevantViews(self.view);
    }
}

%end

%ctor {
    @autoreleasepool {
        NSString *bundleID = NSBundle.mainBundle.bundleIdentifier ?: @"unknown";
        if (![bundleID isEqualToString:@"com.kevin.pinatv"]) {
            PinaTVLabEnabled = NO;
            return;
        }
        PinaTVLabLog(@"Loaded for PinaTV. Resolution preference enabled; ad handling is diagnostic only.");
    }
}
