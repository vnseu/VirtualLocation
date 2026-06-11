//
//  VirtualLocationLoader.m
//  Dylib 入口 — Constructor 自动初始化
//
//  当 dylib 被加载到目标 App 进程时，__attribute__((constructor))
//  确保在 main() 之前执行 Hook 安装。
//

#import "VirtualLocation.h"

// ============================================================
//  配置文件变化监控（热更新）
// ============================================================

@interface VLocConfigMonitor : NSObject
+ (void)startMonitoring;
@end

@implementation VLocConfigMonitor

+ (void)startMonitoring {
    static dispatch_source_t source = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *configPath = @"/var/mobile/Documents/.vloc_config.plist";

        int fd = open(configPath.UTF8String, O_EVTONLY);
        if (fd < 0) {
            // 尝试其他路径
            configPath = [NSString stringWithFormat:@"%@/.vloc_config.plist",
                          NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                               NSUserDomainMask, YES).firstObject];
            fd = open(configPath.UTF8String, O_EVTONLY);
        }

        if (fd >= 0) {
            unsigned long mask = DISPATCH_VNODE_WRITE | DISPATCH_VNODE_DELETE |
                                 DISPATCH_VNODE_EXTEND | DISPATCH_VNODE_RENAME;
            source = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, fd, mask,
                                             dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));

            dispatch_source_set_event_handler(source, ^{
                NSLog(@"[VirtualLocation] 🔄 检测到配置文件变化，热重载...");
                VLocConfigReload();
            });

            dispatch_source_set_cancel_handler(source, ^{
                close(fd);
            });

            dispatch_resume(source);
            NSLog(@"[VirtualLocation] 👁️ 配置文件监控已启动: %@", configPath);
        } else {
            NSLog(@"[VirtualLocation] ⚠️ 无法打开配置文件进行监控");
        }
    });
}

@end

// ============================================================
//  Dylib 入口
// ============================================================

__attribute__((constructor))
static void VirtualLocationLoaderInit(void) {
    @try {
        @autoreleasepool {
            NSLog(@"[VirtualLocation] Dylib loaded, initializing...");

            VLocConfig cfg = VLocConfigLoad();
            VLocHookInstall();
            [VLocConfigMonitor startMonitoring];

            if (cfg.enabled) {
                NSLog(@"[VirtualLocation] Active: (%.6f, %.6f)",
                      cfg.latitude, cfg.longitude);
            } else {
                NSLog(@"[VirtualLocation] Disabled, set location via app");
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[VirtualLocation] Init failed (app continues): %@", e);
    }
}
