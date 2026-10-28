#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

static BOOL PinaTVLabQualityEnabled = NO;
static void (*PinaTVLabOriginalSetMaximumResolution)(id, SEL, CGSize);
static void (*PinaTVLabOriginalSetPeakBitRate)(id, SEL, double);
static id (*PinaTVLabOriginalInitWithURL)(id, SEL, NSURL *);
static id (*PinaTVLabOriginalInitWithAsset)(id, SEL, AVAsset *);
static void (*PinaTVLabOriginalViewDidAppear)(UIViewController *, SEL, BOOL);
static char PinaTVLabButtonAssociationKey;
static char PinaTVLabButtonTargetAssociationKey;

static void PinaTVLabWriteLog(NSString *message) {
    NSLog(@"[PinaTVLabQuality] %@", message);
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

static void PinaTVLabLogURL(NSURL *url) {
    if (!url) return;
    // Never log query or fragment values: signed playback URLs may contain credentials.
    NSString *host = url.host.length ? url.host : @"<no-host>";
    NSString *path = url.path.length ? url.path : @"/";
    PinaTVLabWriteLog([NSString stringWithFormat:@"media host/path: %@%@", host, path]);
}

static void PinaTVLabApplyQualityPreferences(AVPlayerItem *item) {
    if (!item || !PinaTVLabQualityEnabled) return;
    if (PinaTVLabOriginalSetMaximumResolution) {
        PinaTVLabOriginalSetMaximumResolution(item, @selector(setPreferredMaximumResolution:), CGSizeMake(1920.0, 1080.0));
    }
    if (PinaTVLabOriginalSetPeakBitRate) {
        // No client-side bitrate ceiling; actual quality still depends on available authorized renditions/network.
        PinaTVLabOriginalSetPeakBitRate(item, @selector(setPreferredPeakBitRate:), 0.0);
    }
}

static void PinaTVLabHookSetMaximumResolution(id self, SEL selector, CGSize requested) {
    if (!PinaTVLabOriginalSetMaximumResolution) return;
    if (!PinaTVLabQualityEnabled) {
        PinaTVLabOriginalSetMaximumResolution(self, selector, requested);
        return;
    }
    PinaTVLabOriginalSetMaximumResolution(self, selector, CGSizeMake(1920.0, 1080.0));
}

static void PinaTVLabHookSetPeakBitRate(id self, SEL selector, double requested) {
    if (!PinaTVLabOriginalSetPeakBitRate) return;
    if (!PinaTVLabQualityEnabled) {
        PinaTVLabOriginalSetPeakBitRate(self, selector, requested);
        return;
    }
    PinaTVLabOriginalSetPeakBitRate(self, selector, 0.0);
}

static id PinaTVLabHookInitWithURL(id self, SEL selector, NSURL *url) {
    id item = PinaTVLabOriginalInitWithURL ? PinaTVLabOriginalInitWithURL(self, selector, url) : nil;
    if (PinaTVLabQualityEnabled && item) {
        PinaTVLabLogURL(url);
        PinaTVLabApplyQualityPreferences((AVPlayerItem *)item);
    }
    return item;
}

static id PinaTVLabHookInitWithAsset(id self, SEL selector, AVAsset *asset) {
    id item = PinaTVLabOriginalInitWithAsset ? PinaTVLabOriginalInitWithAsset(self, selector, asset) : nil;
    if (PinaTVLabQualityEnabled && item) {
        if ([asset isKindOfClass:[AVURLAsset class]]) {
            PinaTVLabLogURL(((AVURLAsset *)asset).URL);
        }
        PinaTVLabApplyQualityPreferences((AVPlayerItem *)item);
    }
    return item;
}

static AVPlayerLayer *PinaTVLabFindPlayerLayer(CALayer *layer) {
    Class playerLayerClass = objc_getClass("AVPlayerLayer");
    if (!layer || !playerLayerClass) return nil;
    if ([layer isKindOfClass:playerLayerClass]) {
        AVPlayerLayer *playerLayer = (AVPlayerLayer *)layer;
        if (playerLayer.player) return playerLayer;
    }
    for (CALayer *child in layer.sublayers) {
        AVPlayerLayer *found = PinaTVLabFindPlayerLayer(child);
        if (found) return found;
    }
    return nil;
}

static void PinaTVLabShowMessage(UIViewController *controller, NSString *title, NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!controller || !controller.viewIfLoaded.window) return;
        UIViewController *presenter = controller;
        while (presenter.presentedViewController && !presenter.presentedViewController.isBeingDismissed) {
            presenter = presenter.presentedViewController;
        }
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
            message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [presenter presentViewController:alert animated:YES completion:nil];
    });
}

static NSString *PinaTVLabAttribute(NSString *attributes, NSString *name) {
    NSString *pattern = [NSString stringWithFormat:@"(?:^|,)\\s*%@=([^,]+)", name];
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:attributes options:0 range:NSMakeRange(0, attributes.length)];
    if (!match || match.numberOfRanges < 2) return nil;
    NSString *value = [attributes substringWithRange:[match rangeAtIndex:1]];
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\\\""]];
}

static NSURL *PinaTVLabFind1080Variant(NSString *manifest, NSURL *masterURL) {
    NSArray<NSString *> *lines = [manifest componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSInteger pendingWidth = 0, pendingHeight = 0, pendingBandwidth = 0;
    NSURL *bestURL = nil;
    NSInteger bestBandwidth = -1;

    for (NSString *rawLine in lines) {
        NSString *line = [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!line.length) continue;
        if ([line hasPrefix:@"#EXT-X-STREAM-INF:"]) {
            NSString *attributes = [line substringFromIndex:[@"#EXT-X-STREAM-INF:" length]];
            NSString *resolution = PinaTVLabAttribute(attributes, @"RESOLUTION");
            NSArray<NSString *> *dimensions = [resolution componentsSeparatedByString:@"x"];
            pendingWidth = dimensions.count == 2 ? dimensions[0].integerValue : 0;
            pendingHeight = dimensions.count == 2 ? dimensions[1].integerValue : 0;
            pendingBandwidth = [PinaTVLabAttribute(attributes, @"AVERAGE-BANDWIDTH") integerValue];
            if (pendingBandwidth <= 0) pendingBandwidth = [PinaTVLabAttribute(attributes, @"BANDWIDTH") integerValue];
            continue;
        }
        if ([line hasPrefix:@"#"]) continue;
        if (pendingHeight > 0) {
            if (pendingHeight == 1080 && pendingWidth >= 1920 && pendingBandwidth > bestBandwidth) {
                NSURL *candidate = [NSURL URLWithString:line relativeToURL:masterURL].absoluteURL;
                // Preserve a master URL query only for same-host relative renditions that omit one.
                if (candidate && candidate.query.length == 0 && masterURL.query.length > 0 &&
                    [candidate.host.lowercaseString isEqualToString:masterURL.host.lowercaseString]) {
                    NSURLComponents *components = [NSURLComponents componentsWithURL:candidate resolvingAgainstBaseURL:NO];
                    components.query = masterURL.query;
                    candidate = components.URL;
                }
                if (candidate) {
                    bestURL = candidate;
                    bestBandwidth = pendingBandwidth;
                }
            }
            pendingWidth = 0;
            pendingHeight = 0;
            pendingBandwidth = 0;
        }
    }
    return bestURL;
}

@interface PinaTVLabQualityButtonTarget : NSObject
@property(nonatomic, weak) UIViewController *controller;
- (void)choose1080:(UIButton *)sender;
@end

@implementation PinaTVLabQualityButtonTarget
- (void)choose1080:(UIButton *)sender {
    UIViewController *controller = self.controller;
    AVPlayerLayer *playerLayer = PinaTVLabFindPlayerLayer(controller.view.layer);
    AVPlayer *player = playerLayer.player;
    AVPlayerItem *oldItem = player.currentItem;
    if (!oldItem || ![oldItem.asset isKindOfClass:[AVURLAsset class]]) {
        PinaTVLabShowMessage(controller, @"1080p unavailable", @"This player does not expose a selectable HLS master playlist.");
        return;
    }

    NSURL *masterURL = ((AVURLAsset *)oldItem.asset).URL;
    PinaTVLabLogURL(masterURL);
    sender.enabled = NO;
    [sender setTitle:@"Checking…" forState:UIControlStateNormal];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:masterURL completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            sender.enabled = YES;
            [sender setTitle:@"1080p" forState:UIControlStateNormal];
        });

        if (error || !data || ([response isKindOfClass:[NSHTTPURLResponse class]] &&
            ((NSHTTPURLResponse *)response).statusCode >= 400)) {
            PinaTVLabWriteLog([NSString stringWithFormat:@"1080p selection failed while loading playlist: %@", error.localizedDescription ?: @"HTTP error"]);
            PinaTVLabShowMessage(controller, @"Could not load quality options", @"The current stream's playlist could not be fetched with the active session. Playback was not changed.");
            return;
        }

        NSString *manifest = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSURL *variantURL = manifest ? PinaTVLabFind1080Variant(manifest, masterURL) : nil;
        if (!variantURL) {
            PinaTVLabWriteLog(@"no 1920x1080 rendition advertised by the active playlist");
            PinaTVLabShowMessage(controller, @"1080p not available", @"The current playlist did not provide an accessible 1920×1080 rendition. Playback was not changed.");
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (!player || player.currentItem != oldItem) {
                PinaTVLabShowMessage(controller, @"Stream changed", @"The active video changed while checking quality. Try again on the current episode.");
                return;
            }
            BOOL wasPlaying = player.rate != 0.0f;
            float oldRate = player.rate;
            CMTime oldTime = player.currentTime;
            AVPlayerItem *newItem = [AVPlayerItem playerItemWithURL:variantURL];
            PinaTVLabApplyQualityPreferences(newItem);
            [player replaceCurrentItemWithPlayerItem:newItem];
            if (CMTIME_IS_VALID(oldTime) && CMTIME_IS_NUMERIC(oldTime) && CMTimeGetSeconds(oldTime) >= 0.0) {
                [player seekToTime:oldTime toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
                    if (finished && wasPlaying) {
                        [player play];
                        if (oldRate > 0.0f && oldRate != 1.0f) player.rate = oldRate;
                    }
                }];
            } else if (wasPlaying) {
                [player play];
                if (oldRate > 0.0f && oldRate != 1.0f) player.rate = oldRate;
            }
            [sender setTitle:@"1080p ✓" forState:UIControlStateNormal];
            PinaTVLabWriteLog([NSString stringWithFormat:@"selected advertised 1080p rendition: %@%@", variantURL.host ?: @"", variantURL.path ?: @"/"]);
            PinaTVLabShowMessage(controller, @"1080p selected", @"Switched to the playlist's advertised 1920×1080 rendition. The server must permit access to that stream.");
        });
    }];
    [task resume];
}
@end

static void PinaTVLabAddQualityButton(UIViewController *controller) {
    if (!controller || !controller.isViewLoaded || !controller.view.window) return;
    if (objc_getAssociatedObject(controller, &PinaTVLabButtonAssociationKey)) return;
    if (!PinaTVLabFindPlayerLayer(controller.view.layer)) return;

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:@"1080p" forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.90];
    button.layer.cornerRadius = 10.0;
    button.layer.borderWidth = 1.0;
    button.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.25].CGColor;
    button.translatesAutoresizingMaskIntoConstraints = NO;

    PinaTVLabQualityButtonTarget *target = [PinaTVLabQualityButtonTarget new];
    target.controller = controller;
    [button addTarget:target action:@selector(choose1080:) forControlEvents:UIControlEventTouchUpInside];
    objc_setAssociatedObject(button, &PinaTVLabButtonTargetAssociationKey, target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [controller.view addSubview:button];
    [NSLayoutConstraint activateConstraints:@[
        [button.topAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.topAnchor constant:12.0],
        [button.trailingAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.trailingAnchor constant:-14.0],
        [button.widthAnchor constraintEqualToConstant:76.0],
        [button.heightAnchor constraintEqualToConstant:40.0]
    ]];
    objc_setAssociatedObject(controller, &PinaTVLabButtonAssociationKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    PinaTVLabWriteLog([NSString stringWithFormat:@"added manual 1080p button to player controller %@", NSStringFromClass(controller.class)]);
}

static void PinaTVLabHookViewDidAppear(UIViewController *self, SEL selector, BOOL animated) {
    if (PinaTVLabOriginalViewDidAppear) PinaTVLabOriginalViewDidAppear(self, selector, animated);
    if (!PinaTVLabQualityEnabled) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        PinaTVLabAddQualityButton(self);
    });
}

static void PinaTVLabInstallMethodHook(Class cls, SEL selector, IMP replacement, IMP *originalOut) {
    if (!cls || !selector || !replacement || !originalOut) return;
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) {
        PinaTVLabWriteLog([NSString stringWithFormat:@"method unavailable: %@ %@",
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
        PinaTVLabQualityEnabled = YES;

        Class itemClass = objc_getClass("AVPlayerItem");
        PinaTVLabInstallMethodHook(itemClass, @selector(setPreferredMaximumResolution:),
            (IMP)PinaTVLabHookSetMaximumResolution, (IMP *)&PinaTVLabOriginalSetMaximumResolution);
        PinaTVLabInstallMethodHook(itemClass, @selector(setPreferredPeakBitRate:),
            (IMP)PinaTVLabHookSetPeakBitRate, (IMP *)&PinaTVLabOriginalSetPeakBitRate);
        PinaTVLabInstallMethodHook(itemClass, @selector(initWithURL:),
            (IMP)PinaTVLabHookInitWithURL, (IMP *)&PinaTVLabOriginalInitWithURL);
        PinaTVLabInstallMethodHook(itemClass, @selector(initWithAsset:),
            (IMP)PinaTVLabHookInitWithAsset, (IMP *)&PinaTVLabOriginalInitWithAsset);
        PinaTVLabInstallMethodHook(UIViewController.class, @selector(viewDidAppear:),
            (IMP)PinaTVLabHookViewDidAppear, (IMP *)&PinaTVLabOriginalViewDidAppear);

        PinaTVLabWriteLog(@"manual 1080p selector loaded; does not alter VIP/purchase state and only switches to an accessible advertised HLS rendition");
    }
}
