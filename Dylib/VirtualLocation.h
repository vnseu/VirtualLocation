//
//  VirtualLocation.h
//  TrollStore 全局虚拟定位 Dylib
//
//  注入目标 App 后自动 Hook CoreLocation 全家桶
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

// ============================================================
//  配置结构
// ============================================================

typedef struct {
    BOOL enabled;
    double latitude;
    double longitude;
    double altitude;
    double horizontalAccuracy;
    double verticalAccuracy;
    double speed;
    double course;
    NSTimeInterval timestamp;  // epoch seconds
} VLocConfig;

// ============================================================
//  Config Reader
// ============================================================

/// 从共享 plist 读取配置，返回默认值如果文件不存在
VLocConfig VLocConfigLoad(void);

/// 重新加载配置（热更新，无需重启目标 App）
void VLocConfigReload(void);

/// 获取当前配置
VLocConfig VLocConfigGet(void);

// ============================================================
//  Hook Engine
// ============================================================

/// 安装所有 Hook（在 dylib constructor 中自动调用）
void VLocHookInstall(void);

/// 卸载所有 Hook
void VLocHookUninstall(void);
