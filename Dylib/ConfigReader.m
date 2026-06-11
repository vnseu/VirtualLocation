//
//  ConfigReader.m
//  从共享 plist 读取虚拟定位配置
//

#import "VirtualLocation.h"
#import <UIKit/UIKit.h>

// 配置文件的可能路径（按优先级）
static NSArray<NSString *> *configPaths(void) {
    return @[
        // App Group 共享容器（推荐）
        [NSString stringWithFormat:@"%@/group.com.virtuallocation.shared/.vloc_config.plist",
            NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject
                ?: @"/var/mobile/Library"],
        // 全局可读写路径
        @"/var/mobile/Documents/.vloc_config.plist",
        @"/var/mobile/Library/Caches/.vloc_config.plist",
        // App 自身 Documents
        [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject
            stringByAppendingPathComponent:@".vloc_config.plist"],
    ];
}

static VLocConfig sCurrentConfig = {
    .enabled = NO,
    .latitude = 31.2304,    // 默认：上海
    .longitude = 121.4737,
    .altitude = 10.0,
    .horizontalAccuracy = 5.0,
    .verticalAccuracy = 5.0,
    .speed = 0.0,
    .course = 0.0,
    .timestamp = 0,
};

VLocConfig VLocConfigLoad(void) {
    NSDictionary *dict = nil;

    for (NSString *path in configPaths()) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            dict = [NSDictionary dictionaryWithContentsOfFile:path];
            if (dict) {
                NSLog(@"[VirtualLocation] ✅ 配置加载自: %@", path);
                break;
            }
        }
    }

    if (!dict) {
        NSLog(@"[VirtualLocation] ⚠️ 未找到配置文件，使用默认值"
              @" (lat=%.4f, lon=%.4f, enabled=%d)",
              sCurrentConfig.latitude, sCurrentConfig.longitude, sCurrentConfig.enabled);
        return sCurrentConfig;
    }

    sCurrentConfig.enabled = [dict[@"enabled"] boolValue];
    sCurrentConfig.latitude = [dict[@"latitude"] doubleValue];
    sCurrentConfig.longitude = [dict[@"longitude"] doubleValue];

    if (dict[@"altitude"])
        sCurrentConfig.altitude = [dict[@"altitude"] doubleValue];
    if (dict[@"horizontalAccuracy"])
        sCurrentConfig.horizontalAccuracy = [dict[@"horizontalAccuracy"] doubleValue];
    if (dict[@"verticalAccuracy"])
        sCurrentConfig.verticalAccuracy = [dict[@"verticalAccuracy"] doubleValue];
    if (dict[@"speed"])
        sCurrentConfig.speed = [dict[@"speed"] doubleValue];
    if (dict[@"course"])
        sCurrentConfig.course = [dict[@"course"] doubleValue];
    if (dict[@"timestamp"]) {
        NSDate *ts = dict[@"timestamp"];
        sCurrentConfig.timestamp = ts ? [ts timeIntervalSince1970] : 0;
    }

    NSLog(@"[VirtualLocation] 📍 配置: lat=%.6f lon=%.6f alt=%.1f "
          @"enabled=%d speed=%.1f",
          sCurrentConfig.latitude, sCurrentConfig.longitude,
          sCurrentConfig.altitude, sCurrentConfig.enabled,
          sCurrentConfig.speed);

    return sCurrentConfig;
}

void VLocConfigReload(void) {
    VLocConfigLoad();
}

VLocConfig VLocConfigGet(void) {
    return sCurrentConfig;
}
