#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

static BOOL PinaTVLabQualityEnabled = NO;
static void (*PinaTVLabOriginalSetMaximumResolution)(id, SEL, CGSize);
static void (*PinaTVLabOriginalSetPeakBitRate)(id, SEL, double);
static id (*PinaTVLabOriginalInitWithURL)(id, SEL, NSURL *);
static id (*PinaTVLabOriginalInitWithAsset)(id, SEL, AVAsset *);

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
    // Query and fragment can contain signed credentials, so never log them.
    NSString *host = url.host.length ? url.host : @"<no-host>";
    NSString *path = url.path.length ? url.path : @"/";
    PinaTVLabWriteLog([NSString stringWithFormat:@"media host/path: %@%@", host, path]);
}

static void PinaTVLabApplyQualityPreferences(AVPlayerItem *item) {
    if (!item || !PinaTVLabQualityEnabled) return;

    CGSize preferred = CGSizeMake(1920.0, 1080.0);
    if (PinaTVLabOriginalSetMaximumResolution) {
        PinaTVLabOriginalSetMaximumResolution(item, @selector(setPreferredMaximumResolution:), preferred);
        PinaTVLabWriteLog(@"requested preferredMaximumResolution 1920x1080");
    } else {
        PinaTVLabWriteLog(@"preferredMaximumResolution setter unavailable on this iOS version");
    }

    // Zero means no client-side preferred peak bitrate cap; it does not invent bandwidth or source quality.
    if (PinaTVLabOriginalSetPeakBitRate) {
        PinaTVLabOriginalSetPeakBitRate(item, @selector(setPreferredPeakBitRate:), 0.0);
        PinaTVLabWriteLog(@"removed AVPlayerItem preferred peak-bitrate cap");
    }
}

static char PinaTVLabObserverAssociationKey;

@interface PinaTVLabQualityObserver : NSObject
@property(nonatomic, weak) AVPlayerItem *item;
- (instancetype)initWithItem:(AVPlayerItem *)item;
@end

@implementation PinaTVLabQualityObserver

- (instancetype)initWithItem:(AVPlayerItem *)item {
    self = [super init];
    if (self) {
        _item = item;
        @try {
            [item addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:NULL];
            [item addObserver:self forKeyPath:@"presentationSize" options:NSKeyValueObservingOptionNew context:NULL];
        } @catch (NSException *exception) {
            PinaTVLabWriteLog([NSString stringWithFormat:@"could not observe player item: %@", exception.name]);
        }
    }
    return self;
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                     ofObject:(id)object
                       change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                      context:(void *)context {
    if (object != self.item) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }

    if ([keyPath isEqualToString:@"presentationSize"]) {
        CGSize size = self.item.presentationSize;
        if (size.width > 0 && size.height > 0) {
            PinaTVLabWriteLog([NSString stringWithFormat:@"actual video presentation size: %.0fx%.0f", size.width, size.height]);
        }
    } else if ([keyPath isEqualToString:@"status"]) {
        if (self.item.status == AVPlayerItemStatusReadyToPlay) {
            CGSize size = self.item.presentationSize;
            PinaTVLabWriteLog([NSString stringWithFormat:@"player item ready; current presentation size %.0fx%.0f", size.width, size.height]);
        } else if (self.item.status == AVPlayerItemStatusFailed) {
            NSString *reason = self.item.error.localizedDescription ?: @"unknown AVPlayerItem error";
            PinaTVLabWriteLog([NSString stringWithFormat:@"player item failed: %@", reason]);
        }
    }
}

- (void)dealloc {
    AVPlayerItem *item = self.item;
    if (!item) return;
    @try {
        [item removeObserver:self forKeyPath:@"status"];
        [item removeObserver:self forKeyPath:@"presentationSize"];
    } @catch (__unused NSException *exception) {
    }
}
@end

static void PinaTVLabAttachObserver(AVPlayerItem *item) {
    if (!item) return;
    PinaTVLabQualityObserver *observer = [[PinaTVLabQualityObserver alloc] initWithItem:item];
    objc_setAssociatedObject(item, &PinaTVLabObserverAssociationKey, observer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void PinaTVLabHookSetMaximumResolution(id self, SEL selector, CGSize requested) {
    if (!PinaTVLabOriginalSetMaximumResolution) return;
    if (!PinaTVLabQualityEnabled) {
        PinaTVLabOriginalSetMaximumResolution(self, selector, requested);
        return;
    }
    CGSize preferred = CGSizeMake(1920.0, 1080.0);
    if (requested.width != preferred.width || requested.height != preferred.height) {
        PinaTVLabWriteLog([NSString stringWithFormat:@"overrode requested maximum resolution %.0fx%.0f -> 1920x1080",
                           requested.width, requested.height]);
    }
    PinaTVLabOriginalSetMaximumResolution(self, selector, preferred);
}

static void PinaTVLabHookSetPeakBitRate(id self, SEL selector, double requested) {
    if (!PinaTVLabOriginalSetPeakBitRate) return;
    if (!PinaTVLabQualityEnabled) {
        PinaTVLabOriginalSetPeakBitRate(self, selector, requested);
        return;
    }
    if (requested > 0.0) {
        PinaTVLabWriteLog([NSString stringWithFormat:@"removed client bitrate cap of %.0f bits/sec", requested]);
    }
    PinaTVLabOriginalSetPeakBitRate(self, selector, 0.0);
}

static id PinaTVLabHookInitWithURL(id self, SEL selector, NSURL *url) {
    id item = PinaTVLabOriginalInitWithURL ? PinaTVLabOriginalInitWithURL(self, selector, url) : nil;
    if (PinaTVLabQualityEnabled && item) {
        PinaTVLabLogURL(url);
        PinaTVLabApplyQualityPreferences((AVPlayerItem *)item);
        PinaTVLabAttachObserver((AVPlayerItem *)item);
    }
    return item;
}

static id PinaTVLabHookInitWithAsset(id self, SEL selector, AVAsset *asset) {
    id item = PinaTVLabOriginalInitWithAsset ? PinaTVLabOriginalInitWithAsset(self, selector, asset) : nil;
    if (PinaTVLabQualityEnabled && item) {
        if ([asset isKindOfClass:[AVURLAsset class]]) {
            PinaTVLabLogURL(((AVURLAsset *)asset).URL);
        } else {
            PinaTVLabWriteLog([NSString stringWithFormat:@"AVPlayerItem initialized with asset class %@", NSStringFromClass(asset.class)]);
        }
        PinaTVLabApplyQualityPreferences((AVPlayerItem *)item);
        PinaTVLabAttachObserver((AVPlayerItem *)item);
    }
    return item;
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

        PinaTVLabWriteLog(@"quality-only mode loaded; no UIKit hooks, ad suppression, or VIP/purchase-state changes");
    }
}
