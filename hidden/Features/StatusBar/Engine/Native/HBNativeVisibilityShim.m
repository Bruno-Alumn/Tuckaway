//
//  HBNativeVisibilityShim.m
//  Hidden Bar
//
//  Copyright © 2026 Dwarves Foundation. All rights reserved.
//

#import "HBNativeVisibilityShim.h"

static NSString *const HBNativeVisibilityErrorDomain = @"HBNativeVisibility";

static NSError *HBNativeVisibilityError(NSString *reason) {
    return [NSError errorWithDomain:HBNativeVisibilityErrorDomain
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: reason}];
}

#if HIDDENBAR_NATIVE_VISIBILITY

#import <dlfcn.h>
#import <objc/message.h>

// MenuBarClientCore is the private framework behind macOS 27's assessment
// (exam lockdown) mode, which can restrict the menu bar to an allow-list. It is
// resolved at runtime so a macOS release that changes or removes it turns into
// "unavailable" rather than a launch failure. Names are spelled out on purpose.
static NSString *const HBFrameworkPath = @"/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore";
static NSString *const HBConfigurationClassName = @"MBAssessmentModeConfiguration";
static NSString *const HBAssertionClassName = @"MBAssessmentModeAssertion";

static SEL HBConfigurationInit(void) { return @selector(initWithAllowedSystemItems:allowedBundleIdentifiers:); }
static SEL HBActivate(void) { return @selector(activateWithConfiguration:completionHandler:); }
static SEL HBInvalidate(void) { return @selector(invalidate); }
// MenuBarAgent's own request, which names the items to keep by position. See
// HBNativeVisibilityActivateKeepingPositions in the header.
static NSString *const HBItemClassName = @"MBMenuBarItem";
static NSString *const HBItemContentClassName = @"MBMenuBarItemContent";
static SEL HBItemInit(void) { return @selector(initWithID:content:); }
static SEL HBItemContentInit(void) { return @selector(initWithTitle:); }

static BOOL HBPositionsAreAvailable(void) {
    Class item = NSClassFromString(HBItemClassName);
    Class content = NSClassFromString(HBItemContentClassName);
    NSObject *assertion = NSClassFromString(HBAssertionClassName) ? [[NSClassFromString(HBAssertionClassName) alloc] init] : nil;
    return item && content && assertion && [item instancesRespondToSelector:HBItemInit()]
        && [content instancesRespondToSelector:HBItemContentInit()]
        && [assertion respondsToSelector:@selector(activate:completion:)];
}

BOOL HBNativeVisibilityIsAvailable(void) {
    static dispatch_once_t onceToken;
    static BOOL available;
    dispatch_once(&onceToken, ^{
        if (!dlopen(HBFrameworkPath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL)) {
            available = NO;
            return;
        }
        Class configuration = NSClassFromString(HBConfigurationClassName);
        Class assertion = NSClassFromString(HBAssertionClassName);
        available = configuration && assertion
            && [configuration instancesRespondToSelector:HBConfigurationInit()]
            && [assertion instancesRespondToSelector:HBActivate()]
            && [assertion instancesRespondToSelector:HBInvalidate()];
    });
    return available;
}

void HBNativeVisibilityActivate(NSArray<NSNumber *> *allowedSystemItems,
                                NSArray<NSString *> *allowedBundleIdentifiers,
                                void (^completion)(id _Nullable assertion, NSError * _Nullable error)) {
    void (^finish)(id, NSError *) = ^(id assertion, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(assertion, error); });
    };
    if (!HBNativeVisibilityIsAvailable()) {
        finish(nil, HBNativeVisibilityError(@"MenuBarClientCore is unavailable on this macOS"));
        return;
    }
    @try {
        // Both lists must be NSArrays: the framework indexes into them, and an
        // NSSet raises -objectAtIndex: unrecognized.
        id configuration = ((id (*)(id, SEL, NSArray *, NSArray *))objc_msgSend)(
            [NSClassFromString(HBConfigurationClassName) alloc], HBConfigurationInit(),
            [allowedSystemItems copy], [allowedBundleIdentifiers copy]);
        id assertion = [[NSClassFromString(HBAssertionClassName) alloc] init];
        if (!configuration || !assertion) {
            finish(nil, HBNativeVisibilityError(@"Could not create the visibility configuration"));
            return;
        }
        ((void (*)(id, SEL, id, void (^)(NSError *)))objc_msgSend)(
            assertion, HBActivate(), configuration, ^(NSError *error) {
                finish(error ? nil : assertion, error);
            });
    } @catch (NSException *exception) {
        finish(nil, HBNativeVisibilityError([NSString stringWithFormat:@"%@: %@", exception.name, exception.reason]));
    }
}

void HBNativeVisibilityActivateKeepingPositions(NSArray<NSNumber *> *itemCenters,
                                                void (^completion)(id _Nullable assertion, NSError * _Nullable error)) {
    void (^finish)(id, NSError *) = ^(id assertion, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(assertion, error); });
    };
    if (!HBNativeVisibilityIsAvailable()) {
        finish(nil, HBNativeVisibilityError(@"MenuBarClientCore is unavailable on this macOS"));
        return;
    }
    if (!HBPositionsAreAvailable()) {
        finish(nil, HBNativeVisibilityError(@"This macOS cannot keep menu-bar items by position"));
        return;
    }
    @try {
        id configuration = ((id (*)(id, SEL))objc_msgSend)([NSClassFromString(HBConfigurationClassName) alloc], @selector(initWithUnrestrictedMenuBarItems));
        id assertion = [[NSClassFromString(HBAssertionClassName) alloc] init];
        if (!configuration || !assertion) {
            finish(nil, HBNativeVisibilityError(@"Could not create the visibility configuration"));
            return;
        }
        NSMutableArray *items = [NSMutableArray array];
        for (NSNumber *center in itemCenters) {
            NSString *itemID = [NSString stringWithFormat:@"%.0f", center.doubleValue / HBNativeVisibilityPositionTolerance];
            id content = ((id (*)(id, SEL, NSString *))objc_msgSend)([NSClassFromString(HBItemContentClassName) alloc],
                                                                    HBItemContentInit(), itemID);
            id item = ((id (*)(id, SEL, NSString *, id))objc_msgSend)([NSClassFromString(HBItemClassName) alloc],
                                                                     HBItemInit(), itemID, content);
            if (item) { [items addObject:item]; }
        }
        ((void (*)(id, SEL, id, void (^)(NSError *)))objc_msgSend)(
            assertion, @selector(activate:completion:), configuration, ^(NSError *error) {
                finish(error ? nil : assertion, error);
            });
    } @catch (NSException *exception) {
        finish(nil, HBNativeVisibilityError([NSString stringWithFormat:@"%@: %@", exception.name, exception.reason]));
    }
}

void HBNativeVisibilityInvalidate(id assertion) {
    @try {
        if ([assertion respondsToSelector:HBInvalidate()]) {
            ((void (*)(id, SEL))objc_msgSend)(assertion, HBInvalidate());
        }
    } @catch (NSException *exception) {
        NSLog(@"NativeVisibility: invalidate raised %@: %@", exception.name, exception.reason);
    }
}

#else

BOOL HBNativeVisibilityIsAvailable(void) {
    return NO;
}

void HBNativeVisibilityActivate(NSArray<NSNumber *> *allowedSystemItems,
                                NSArray<NSString *> *allowedBundleIdentifiers,
                                void (^completion)(id _Nullable assertion, NSError * _Nullable error)) {
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(nil, HBNativeVisibilityError(@"Native visibility is not part of this build"));
    });
}

void HBNativeVisibilityActivateKeepingPositions(NSArray<NSNumber *> *itemCenters,
                                                void (^completion)(id _Nullable assertion, NSError * _Nullable error)) {
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(nil, HBNativeVisibilityError(@"Native visibility is not part of this build"));
    });
}

void HBNativeVisibilityInvalidate(id assertion) {
}

#endif
