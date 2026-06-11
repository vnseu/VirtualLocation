//
//  HookLocation.m
//  CoreLocation 全家桶 Hook — 核心引擎
//
//  劫持链路:
//    CLLocationManager.startUpdatingLocation  → 阻止真实 GPS
//    CLLocationManager.location               → 返回伪造 CLLocation
//    CLLocationManager.requestLocation        → 返回伪造回调
//    CLLocation.coordinate/altitude/speed...   → 返回伪造值
//    CLLocationManagerDelegate 回调             → 注入假定位
//    CLLocationCoordinate2DMake (C 函数)       → fishhook
//

#import "VirtualLocation.h"
#import "fishhook.h"
#import <objc/runtime.h>
#import <objc/message.h>

// ============================================================
//  伪造的 CLLocation 子类（避免创建真实对象时的坐标覆盖）
// ============================================================

@interface VLocFakeLocation : CLLocation
@property (nonatomic, assign) CLLocationCoordinate2D fakeCoordinate;
@property (nonatomic, assign) CLLocationDistance fakeAltitude;
@property (nonatomic, assign) CLLocationAccuracy fakeHorizontalAccuracy;
@property (nonatomic, assign) CLLocationAccuracy fakeVerticalAccuracy;
@property (nonatomic, assign) CLLocationSpeed fakeSpeed;
@property (nonatomic, assign) CLLocationDirection fakeCourse;
@property (nonatomic, strong) NSDate *fakeTimestamp;
@end

@implementation VLocFakeLocation

- (CLLocationCoordinate2D)coordinate {
    return self.fakeCoordinate;
}

- (CLLocationDistance)altitude {
    return self.fakeAltitude;
}

- (CLLocationAccuracy)horizontalAccuracy {
    return self.fakeHorizontalAccuracy;
}

- (CLLocationAccuracy)verticalAccuracy {
    return self.fakeVerticalAccuracy;
}

- (CLLocationSpeed)speed {
    return self.fakeSpeed;
}

- (CLLocationDirection)course {
    return self.fakeCourse;
}

- (NSDate *)timestamp {
    return self.fakeTimestamp ?: [NSDate date];
}

@end

// ============================================================
//  CLLocationCoordinate2DMake Hook (C function)
// ============================================================

static CLLocationCoordinate2D (*orig_CLLocationCoordinate2DMake)(double lat, double lon);

static CLLocationCoordinate2D hooked_CLLocationCoordinate2DMake(double latitude, double longitude) {
    VLocConfig cfg = VLocConfigGet();
    if (cfg.enabled) {
        return orig_CLLocationCoordinate2DMake(cfg.latitude, cfg.longitude);
    }
    return orig_CLLocationCoordinate2DMake(latitude, longitude);
}

// ============================================================
//  CLLocation 坐标 Hook（拦截所有 CLLocation 实例的坐标读取）
// ============================================================

static CLLocationCoordinate2D (*orig_CLLocation_coordinate)(id self, SEL _cmd);

static CLLocationCoordinate2D hooked_CLLocation_coordinate(id self, SEL _cmd) {
    VLocConfig cfg = VLocConfigGet();
    if (!cfg.enabled) {
        return orig_CLLocation_coordinate(self, _cmd);
    }
    CLLocationCoordinate2D fake;
    fake.latitude = cfg.latitude;
    fake.longitude = cfg.longitude;
    return fake;
}

static CLLocationDistance (*orig_CLLocation_altitude)(id self, SEL _cmd);

static CLLocationDistance hooked_CLLocation_altitude(id self, SEL _cmd) {
    VLocConfig cfg = VLocConfigGet();
    if (!cfg.enabled) {
        return orig_CLLocation_altitude(self, _cmd);
    }
    return cfg.altitude;
}

static CLLocationAccuracy (*orig_CLLocation_horizontalAccuracy)(id self, SEL _cmd);

static CLLocationAccuracy hooked_CLLocation_horizontalAccuracy(id self, SEL _cmd) {
    VLocConfig cfg = VLocConfigGet();
    if (!cfg.enabled) {
        return orig_CLLocation_horizontalAccuracy(self, _cmd);
    }
    return cfg.horizontalAccuracy;
}

static CLLocationAccuracy (*orig_CLLocation_verticalAccuracy)(id self, SEL _cmd);

static CLLocationAccuracy hooked_CLLocation_verticalAccuracy(id self, SEL _cmd) {
    VLocConfig cfg = VLocConfigGet();
    if (!cfg.enabled) {
        return orig_CLLocation_verticalAccuracy(self, _cmd);
    }
    return cfg.verticalAccuracy;
}

static CLLocationSpeed (*orig_CLLocation_speed)(id self, SEL _cmd);

static CLLocationSpeed hooked_CLLocation_speed(id self, SEL _cmd) {
    VLocConfig cfg = VLocConfigGet();
    if (!cfg.enabled) {
        return orig_CLLocation_speed(self, _cmd);
    }
    return cfg.speed;
}

static CLLocationDirection (*orig_CLLocation_course)(id self, SEL _cmd);

static CLLocationDirection hooked_CLLocation_course(id self, SEL _cmd) {
    VLocConfig cfg = VLocConfigGet();
    if (!cfg.enabled) {
        return orig_CLLocation_course(self, _cmd);
    }
    return cfg.course;
}

static NSDate * (*orig_CLLocation_timestamp)(id self, SEL _cmd);

static NSDate * hooked_CLLocation_timestamp(id self, SEL _cmd) {
    VLocConfig cfg = VLocConfigGet();
    if (!cfg.enabled) {
        return orig_CLLocation_timestamp(self, _cmd);
    }
    if (cfg.timestamp > 0) {
        return [NSDate dateWithTimeIntervalSince1970:cfg.timestamp];
    }
    return [NSDate date];
}

// ============================================================
//  CLLocationManager Hook
// ============================================================

static void (*orig_CLLocationManager_startUpdatingLocation)(id self, SEL _cmd);

static void hooked_CLLocationManager_startUpdatingLocation(id self, SEL _cmd) {
    VLocConfig cfg = VLocConfigGet();
    if (cfg.enabled) {
        NSLog(@"[VirtualLocation] 🚫 阻止 startUpdatingLocation，注入假定位");
        // 不启动真实 GPS，而是立即注入伪造定位
        // 获取 delegate 并直接回调
        id delegate = ((id (*)(id, SEL))objc_msgSend)(self, @selector(delegate));
        if (delegate && [delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
            // 延迟一点点以确保 delegate 准备好
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
                          dispatch_get_main_queue(), ^{
                [self vl_injectFakeLocations:delegate];
            });
        }
        return;
    }
    orig_CLLocationManager_startUpdatingLocation(self, _cmd);
}

static void (*orig_CLLocationManager_stopUpdatingLocation)(id self, SEL _cmd);

static void hooked_CLLocationManager_stopUpdatingLocation(id self, SEL _cmd) {
    VLocConfig cfg = VLocConfigGet();
    if (cfg.enabled) {
        NSLog(@"[VirtualLocation] 🚫 阻止 stopUpdatingLocation");
        return; // 不停止（因为根本没启动真实 GPS）
    }
    orig_CLLocationManager_stopUpdatingLocation(self, _cmd);
}

static void (*orig_CLLocationManager_requestLocation)(id self, SEL _cmd);

static void hooked_CLLocationManager_requestLocation(id self, SEL _cmd) {
    VLocConfig cfg = VLocConfigGet();
    if (cfg.enabled) {
        NSLog(@"[VirtualLocation] 🚫 劫持 requestLocation");
        // 延迟注入假定位
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)),
                      dispatch_get_main_queue(), ^{
            id delegate = ((id (*)(id, SEL))objc_msgSend)(self, @selector(delegate));
            if (delegate && [delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
                [self vl_injectFakeLocations:delegate];
            }
        });
        return;
    }
    orig_CLLocationManager_requestLocation(self, _cmd);
}

static CLLocation * (*orig_CLLocationManager_location)(id self, SEL _cmd);

static CLLocation * hooked_CLLocationManager_location(id self, SEL _cmd) {
    VLocConfig cfg = VLocConfigGet();
    if (cfg.enabled) {
        return [VLocFakeLocation vl_fakeLocationWithConfig:cfg];
    }
    return orig_CLLocationManager_location(self, _cmd);
}

// ============================================================
//  CLLocationManager setDelegate Hook（拦截 delegate 设置）
// ============================================================

static void (*orig_CLLocationManager_setDelegate)(id self, SEL _cmd, id delegate);

static void hooked_CLLocationManager_setDelegate(id self, SEL _cmd, id delegate) {
    // 保存原始 delegate
    objc_setAssociatedObject(self, @selector(vl_originalDelegate),
                             delegate, OBJC_ASSOCIATION_ASSIGN);

    // 如果 delegate 不为空，尝试 swizzle 它的回调方法
    if (delegate) {
        [self vl_swizzleDelegate:delegate];
    }

    orig_CLLocationManager_setDelegate(self, _cmd, delegate);
}

// ============================================================
//  CLLocationManager Category — 辅助方法
// ============================================================

@interface CLLocationManager (VirtualLocation)
- (void)vl_injectFakeLocations:(id)delegate;
- (void)vl_swizzleDelegate:(id)delegate;
- (id)vl_originalDelegate;
@end

@implementation CLLocationManager (VirtualLocation)

- (void)vl_injectFakeLocations:(id)delegate {
    VLocConfig cfg = VLocConfigGet();
    if (!cfg.enabled) return;

    VLocFakeLocation *fakeLoc = [VLocFakeLocation vl_fakeLocationWithConfig:cfg];
    NSArray *locations = @[fakeLoc];

    NSLog(@"[VirtualLocation] 📍 注入假定位: (%.6f, %.6f) → delegate",
          cfg.latitude, cfg.longitude);

    // 回调 locationManager:didUpdateLocations:
    if ([delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
        ((void (*)(id, SEL, id, NSArray *))objc_msgSend)(
            delegate, @selector(locationManager:didUpdateLocations:), self, locations);
    }

    // 回调 locationManager:didUpdateToLocation:fromLocation: (deprecated but still used)
    if ([delegate respondsToSelector:@selector(locationManager:didUpdateToLocation:fromLocation:)]) {
        ((void (*)(id, SEL, id, CLLocation *, CLLocation *))objc_msgSend)(
            delegate, @selector(locationManager:didUpdateToLocation:fromLocation:),
            self, fakeLoc, fakeLoc);
    }

    // 回调 locationManager:didUpdateHeading:
    // (保持朝向不变，不劫持)
}

- (void)vl_swizzleDelegate:(id)delegate {
    Class delegateClass = object_getClass(delegate);

    // 只对每个 delegate 类 swizzle 一次
    static NSMutableSet *swizzledClasses = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        swizzledClasses = [NSMutableSet set];
    });

    @synchronized(swizzledClasses) {
        NSString *className = NSStringFromClass(delegateClass);
        if ([swizzledClasses containsObject:className]) return;
        [swizzledClasses addObject:className];
    }

    NSLog(@"[VirtualLocation] 🔧 Swizzle delegate class: %@", NSStringFromClass(delegateClass));

    // Swizzle locationManager:didUpdateLocations:
    SEL origDidUpdateSel = @selector(locationManager:didUpdateLocations:);
    Method origDidUpdateMethod = class_getInstanceMethod(delegateClass, origDidUpdateSel);
    if (origDidUpdateMethod) {
        IMP newIMP = imp_implementationWithBlock(^(id _self, CLLocationManager *manager, NSArray<CLLocation *> *locations) {
            VLocConfig cfg = VLocConfigGet();
            if (cfg.enabled) {
                VLocFakeLocation *fakeLoc = [VLocFakeLocation vl_fakeLocationWithConfig:cfg];
                locations = @[fakeLoc];
                NSLog(@"[VirtualLocation] 🎯 劫持 didUpdateLocations: → (%.6f, %.6f)",
                      cfg.latitude, cfg.longitude);
            }
            // 调用原始实现
            ((void (*)(id, SEL, id, NSArray *))objc_msgSend)(
                _self, origDidUpdateSel, manager, locations);
        });
        method_setImplementation(origDidUpdateMethod, newIMP);
    }
}

@end

// ============================================================
//  VLocFakeLocation 工厂方法
// ============================================================

@implementation VLocFakeLocation (Factory)

+ (instancetype)vl_fakeLocationWithConfig:(VLocConfig)cfg {
    CLLocationCoordinate2D coord = CLLocationCoordinate2DMake(cfg.latitude, cfg.longitude);

    VLocFakeLocation *loc = [[VLocFakeLocation alloc] initWithCoordinate:coord
                                                                 altitude:cfg.altitude
                                                       horizontalAccuracy:cfg.horizontalAccuracy
                                                         verticalAccuracy:cfg.verticalAccuracy
                                                                timestamp:cfg.timestamp > 0
                                                                          ? [NSDate dateWithTimeIntervalSince1970:cfg.timestamp]
                                                                          : [NSDate date]];

    loc.fakeCoordinate = coord;
    loc.fakeAltitude = cfg.altitude;
    loc.fakeHorizontalAccuracy = cfg.horizontalAccuracy;
    loc.fakeVerticalAccuracy = cfg.verticalAccuracy;
    loc.fakeSpeed = cfg.speed;
    loc.fakeCourse = cfg.course;
    loc.fakeTimestamp = cfg.timestamp > 0
                        ? [NSDate dateWithTimeIntervalSince1970:cfg.timestamp]
                        : [NSDate date];

    return loc;
}

@end

// ============================================================
//  Hook 安装 / 卸载
// ============================================================

static BOOL sHooksInstalled = NO;

void VLocHookInstall(void) {
    if (sHooksInstalled) {
        NSLog(@"[VirtualLocation] ⚠️ Hook 已安装，跳过");
        return;
    }

    NSLog(@"[VirtualLocation] 🔧 安装 CoreLocation Hook...");

    // --- C 函数 Hook (fishhook) ---
    static struct rebinding c_rebindings[] = {
        {"_CLLocationCoordinate2DMake",
         (void *)hooked_CLLocationCoordinate2DMake,
         (void **)&orig_CLLocationCoordinate2DMake},
    };
    rebind_symbols(c_rebindings, sizeof(c_rebindings) / sizeof(struct rebinding));

    // --- ObjC Method Swizzling ---

    // CLLocation 坐标访问器
    Method m;

    m = class_getInstanceMethod([CLLocation class], @selector(coordinate));
    orig_CLLocation_coordinate = (void *)method_getImplementation(m);
    method_setImplementation(m, (IMP)hooked_CLLocation_coordinate);

    m = class_getInstanceMethod([CLLocation class], @selector(altitude));
    orig_CLLocation_altitude = (void *)method_getImplementation(m);
    method_setImplementation(m, (IMP)hooked_CLLocation_altitude);

    m = class_getInstanceMethod([CLLocation class], @selector(horizontalAccuracy));
    orig_CLLocation_horizontalAccuracy = (void *)method_getImplementation(m);
    method_setImplementation(m, (IMP)hooked_CLLocation_horizontalAccuracy);

    m = class_getInstanceMethod([CLLocation class], @selector(verticalAccuracy));
    orig_CLLocation_verticalAccuracy = (void *)method_getImplementation(m);
    method_setImplementation(m, (IMP)hooked_CLLocation_verticalAccuracy);

    m = class_getInstanceMethod([CLLocation class], @selector(speed));
    orig_CLLocation_speed = (void *)method_getImplementation(m);
    method_setImplementation(m, (IMP)hooked_CLLocation_speed);

    m = class_getInstanceMethod([CLLocation class], @selector(course));
    orig_CLLocation_course = (void *)method_getImplementation(m);
    method_setImplementation(m, (IMP)hooked_CLLocation_course);

    m = class_getInstanceMethod([CLLocation class], @selector(timestamp));
    orig_CLLocation_timestamp = (void *)method_getImplementation(m);
    method_setImplementation(m, (IMP)hooked_CLLocation_timestamp);

    // CLLocationManager
    m = class_getInstanceMethod([CLLocationManager class], @selector(startUpdatingLocation));
    orig_CLLocationManager_startUpdatingLocation = (void *)method_getImplementation(m);
    method_setImplementation(m, (IMP)hooked_CLLocationManager_startUpdatingLocation);

    m = class_getInstanceMethod([CLLocationManager class], @selector(stopUpdatingLocation));
    orig_CLLocationManager_stopUpdatingLocation = (void *)method_getImplementation(m);
    method_setImplementation(m, (IMP)hooked_CLLocationManager_stopUpdatingLocation);

    m = class_getInstanceMethod([CLLocationManager class], @selector(requestLocation));
    orig_CLLocationManager_requestLocation = (void *)method_getImplementation(m);
    method_setImplementation(m, (IMP)hooked_CLLocationManager_requestLocation);

    m = class_getInstanceMethod([CLLocationManager class], @selector(location));
    orig_CLLocationManager_location = (void *)method_getImplementation(m);
    method_setImplementation(m, (IMP)hooked_CLLocationManager_location);

    m = class_getInstanceMethod([CLLocationManager class], @selector(setDelegate:));
    orig_CLLocationManager_setDelegate = (void *)method_getImplementation(m);
    method_setImplementation(m, (IMP)hooked_CLLocationManager_setDelegate);

    sHooksInstalled = YES;
    NSLog(@"[VirtualLocation] ✅ CoreLocation Hook 安装完成！");
}

void VLocHookUninstall(void) {
    if (!sHooksInstalled) return;

    // 恢复 CLLocation
    Method m;
    m = class_getInstanceMethod([CLLocation class], @selector(coordinate));
    method_setImplementation(m, (IMP)orig_CLLocation_coordinate);
    m = class_getInstanceMethod([CLLocation class], @selector(altitude));
    method_setImplementation(m, (IMP)orig_CLLocation_altitude);
    m = class_getInstanceMethod([CLLocation class], @selector(horizontalAccuracy));
    method_setImplementation(m, (IMP)orig_CLLocation_horizontalAccuracy);
    m = class_getInstanceMethod([CLLocation class], @selector(verticalAccuracy));
    method_setImplementation(m, (IMP)orig_CLLocation_verticalAccuracy);
    m = class_getInstanceMethod([CLLocation class], @selector(speed));
    method_setImplementation(m, (IMP)orig_CLLocation_speed);
    m = class_getInstanceMethod([CLLocation class], @selector(course));
    method_setImplementation(m, (IMP)orig_CLLocation_course);
    m = class_getInstanceMethod([CLLocation class], @selector(timestamp));
    method_setImplementation(m, (IMP)orig_CLLocation_timestamp);

    // 恢复 CLLocationManager
    m = class_getInstanceMethod([CLLocationManager class], @selector(startUpdatingLocation));
    method_setImplementation(m, (IMP)orig_CLLocationManager_startUpdatingLocation);
    m = class_getInstanceMethod([CLLocationManager class], @selector(stopUpdatingLocation));
    method_setImplementation(m, (IMP)orig_CLLocationManager_stopUpdatingLocation);
    m = class_getInstanceMethod([CLLocationManager class], @selector(requestLocation));
    method_setImplementation(m, (IMP)orig_CLLocationManager_requestLocation);
    m = class_getInstanceMethod([CLLocationManager class], @selector(location));
    method_setImplementation(m, (IMP)orig_CLLocationManager_location);
    m = class_getInstanceMethod([CLLocationManager class], @selector(setDelegate:));
    method_setImplementation(m, (IMP)orig_CLLocationManager_setDelegate);

    sHooksInstalled = NO;
    NSLog(@"[VirtualLocation] 🔓 Hook 已卸载");
}
