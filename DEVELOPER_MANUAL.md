# VirtualLocation 开发者手册

## 目录
1. [Mach-O 注入详解](#mach-o-注入详解)
2. [Hook 引擎架构](#hook-引擎架构)
3. [配置文件路径策略](#配置文件路径策略)
4. [TrollStore Entitlement 分析](#trollstore-entitlement-分析)
5. [反检测思路](#反检测思路)
6. [已知限制和解决方案](#已知限制和解决方案)

---

## Mach-O 注入详解

### 注入流程

```
原始 IPA
  │
  ├─→ unzip → Payload/Target.app/
  │                              │
  │                              ├─→ Info.plist (读 CFBundleExecutable)
  │                              ├─→ Target (Mach-O arm64)
  │                              └─→ Frameworks/
  │
  ├─→ 步骤 1: Fat Binary 解析
  │   ┌─────────────────────────────┐
  │   │ Fat Header                  │
  │   │  magic: 0xcafebabe          │
  │   │  nfat_arch: 2               │
  │   │  ├─ arm64: offset=0x4000    │  ← 这是我们要修改的
  │   │  └─ arm64e: offset=0x...    │  ← 保留不动
  │   └─────────────────────────────┘
  │
  ├─→ 步骤 2: 插入 LC_LOAD_DYLIB
  │   在 LC_CODE_SIGNATURE 之前插入:
  │   ┌─────────────────────────────┐
  │   │ cmd: LC_LOAD_DYLIB (0x0c)   │
  │   │ cmdsize: aligned             │
  │   │ name: @executable_path/     │
  │   │       VirtualLocation.dylib  │
  │   └─────────────────────────────┘
  │
  ├─→ 步骤 3: 复制 dylib
  │   Target.app/VirtualLocation.dylib
  │
  ├─→ 步骤 4: ldid 伪签名
  │   CoreTrust 漏洞 → 签名验证被绕过
  │
  └─→ 步骤 5: zip → Target_patched.ipa
```

### insert_dylib vs 内置解析器

| 方案 | 优点 | 缺点 |
|------|------|------|
| **insert_dylib** | 成熟稳定，处理 edge case | 需额外安装 |
| **内置 Mach-O 解析器** | 零依赖 | 不处理某些复杂 binary |

patcher.py 优先使用 insert_dylib，不可用时回退到内置解析器。

### 为什么选择 LC_LOAD_DYLIB 而非 LC_LOAD_WEAK_DYLIB

- LC_LOAD_DYLIB：dylib 缺失时 dyld 直接 crash → 更容易发现注入状态
- LC_LOAD_WEAK_DYLIB：dylib 缺失时静默忽略 → 用户可能以为注入了实际没有

---

## Hook 引擎架构

### 分层设计

```
┌─────────────────────────────────────────┐
│ Layer 3: Delegate Proxy                  │
│  swizzle setDelegate: → 包装 delegate    │
│  拦截 didUpdateLocations: 回调            │
├─────────────────────────────────────────┤
│ Layer 2: ObjC Method Swizzling           │
│  CLLocationManager 全部公开方法           │
│  CLLocation 全部属性 getter              │
├─────────────────────────────────────────┤
│ Layer 1: fishhook (C 函数)               │
│  CLLocationCoordinate2DMake             │
│  (可扩展更多 C 函数)                      │
├─────────────────────────────────────────┤
│ Foundation: ConfigReader                 │
│  读取 .vloc_config.plist                 │
│  dispatch_source 监控文件变化 (热更新)     │
└─────────────────────────────────────────┘
```

### 热更新机制

```
VirtualLocation App 写入配置
        │
        ▼
/var/mobile/Documents/.vloc_config.plist
        │
        │ dispatch_source (DISPATCH_VNODE_WRITE)
        ▼
VLocConfigReload()
        │
        ▼
下次 CLLocationManager 回调 → 使用新坐标
（无需重启目标 App）
```

### VLocFakeLocation

自定义 CLLocation 子类，覆盖所有属性 getter：

```objc
@interface VLocFakeLocation : CLLocation
@property (nonatomic, assign) CLLocationCoordinate2D fakeCoordinate;
@property (nonatomic, assign) CLLocationDistance fakeAltitude;
// ... 其他属性
@end

// 每个 getter 返回假值，不走父类实现
- (CLLocationCoordinate2D)coordinate {
    return self.fakeCoordinate;
}
```

选择子类而非 method swizzling CLLocation getter 的原因：
- CLLocation 的 getter 可能在 App 初始化前就被调用
- 子类方式不改变原始 CLLocation 的行为（降低兼容性风险）
- delegate 回调传入的是我们自己的 VLocFakeLocation 实例

---

## 配置文件路径策略

### 写入路径（ConfigWriter）

```
优先级从高到低:
1. /var/mobile/Documents/.vloc_config.plist           ← 最通用
2. /var/mobile/Library/Caches/.vloc_config.plist      ← 备选
3. {AppDocuments}/.vloc_config.plist                  ← App 自身
4. {AppGroup}/.vloc_config.plist                      ← 如果配置了 App Group
```

### 读取路径（ConfigReader）

```
优先级从高到低:
1. {AppGroup}/group.com.virtuallocation.shared/.../   ← App Group
2. /var/mobile/Documents/.vloc_config.plist           ← 全局
3. /var/mobile/Library/Caches/.vloc_config.plist      ← 全局备选
4. {AppDocuments}/.vloc_config.plist                  ← 自身
```

### TrollStore 的文件访问权限

通过 `com.apple.private.security.no-sandbox` entitlement，TrollStore App 可以：
- 读取 `/var/mobile/Documents/` ✅
- 写入 `/var/mobile/Documents/` ✅
- 访问其他 App 的容器 ❌ (需要额外 entitlement)

因此配置文件放在 `/var/mobile/Documents/` 是最可靠的选择。

---

## TrollStore Entitlement 分析

### 必要权限

| Entitlement | 作用 | 必需？ |
|-------------|------|--------|
| `platform-application` | 标记为平台应用 | ✅ 是 |
| `com.apple.private.skip-library-validation` | 加载未签名 dylib | ✅ 是（目标 App 需要） |
| `dynamic-codesigning` | 允许动态代码签名 | ✅ 是 |
| `get-task-allow` | 允许调试 | ✅ 推荐 |
| `com.apple.private.security.no-sandbox` | 无沙盒限制 | ✅ 推荐（写配置文件） |

### 目标 App 是否需要这些权限？

**不需要。** 目标 App 只需要加载 dylib，而 dylib 是通过修改 Mach-O 加载的。iOS 的动态链接器在加载 `LC_LOAD_DYLIB` 时并不检查 dylib 的签名（这是 CoreTrust 漏洞的关键）。

但为了保险，patcher.py 会给目标 App 也加上这些 entitlements。

---

## 反检测思路

### 常见检测手段

| 检测方式 | 原理 | 绕过 |
|----------|------|------|
| `CLLocationManager.location` 是否为特定子类 | 检查 location 的 class | VLocFakeLocation 继承 CLLocation，isKindOfClass 通过 ✅ |
| 多个 LocationManager 实例一致性 | 不同 CLLocationManager 实例返回坐标是否一致 | 所有实例都被 Hook，全局一致 ✅ |
| 时间戳合理性 | timestamp 是否在合理范围内 | 可配置 timestamp ✅ |
| 定位精度是否合理 | horizontalAccuracy 是否为常见值 | 默认 5m（正常 GPS 精度） ✅ |
| altitude 有效性 | 是否在合理范围 | 默认 10m（合理值） ✅ |
| 检测 dylib 是否加载 | `dladdr()` 或 `_dyld_get_image_name()` | 暂无自动绕过，需手动 strip 符号 |
| 检测方法是否被 Swizzle | 比较 IMP 地址 | 暂无绕过 |
| 检测 fishhook | 检查 lazy symbol pointer 是否被修改 | 暂无绕过 |

### 高级反检测方案（TODO）

1. **内核级 Hook**：绕过用户态检测
2. **Virtualization**：虚拟化整个定位子系统
3. **GPX 模拟**：通过 Xcode GPX 机制（需要开发者模式）

---

## 已知限制和解决方案

### 限制 1: 部分 C 函数未被 Hook

当前只 Hook 了 `CLLocationCoordinate2DMake`。某些 App 可能直接调用其他 CoreLocation C API。

**解决方案**: 在 fishhook 的 rebindings 数组中添加更多符号。

### 限制 2: SwiftUI 的 `@StateObject` / `@ObservedObject` 可能绕过 ObjC Hook

Swift 的 CLLocation 包装可能不走 ObjC runtime。

**解决方案**: 这些封装底层仍调用 ObjC 方法，已验证通过。

### 限制 3: App 使用私有 API 直接访问定位硬件

例如直接与 `locationd` daemon 通信。

**解决方案**: TrollStore 无法 hook 系统 daemon，需要越狱。这种情况极少见。

### 限制 4: iOS 17.0.1+ 不支持

CoreTrust 漏洞在 iOS 17.0.1 被修复，TrollStore 无法安装。

**解决方案**: 降级到 iOS 17.0 或以下，或等待新的漏洞。

### 限制 5: 目标 App 每次更新需要重新注入

App Store 更新会覆盖被修改的二进制。

**解决方案**: 使用 TrollStore 的 "Block Updates" 功能阻止自动更新。

---

## 构建系统详解

### 编译器选择

- **Dylib**: `xcrun clang`（可用 GCC/Clang 交叉编译到 arm64-apple-ios）
- **App**: `xcrun swiftc`（Swift 编译器，目标 arm64-apple-ios14.0）

### 为什么不用 Xcode Project？

- Build script 更透明，适合自动化
- 避免 Xcode 版本兼容问题
- 更轻量，无需完整的 `.xcodeproj`

### 交叉编译（macOS → iOS）

```bash
# 关键参数
-target arm64-apple-ios14.0    # 目标架构 + 最低 iOS 版本
-sdk iphoneos                  # 使用 iPhoneOS SDK
-miphoneos-version-min=14.0    # 最低部署目标
```

---

## 调试指南

### 查看 dylib 是否被加载

```bash
# 在设备上用 Filza 或 SSH 查看目标 App 的日志
# 搜索 "VirtualLocation" 关键字
```

### 验证 Hook 是否生效

在 VirtualLocation App 中打开「激活」后，在目标 App 中：

1. 打开内置浏览器访问 `https://maps.google.com` → 应显示假位置
2. 使用定位相关功能 → 坐标应为设定值

### 手动验证配置文件

```bash
# SSH 到设备
ssh root@<device_ip>

# 查看配置
plutil -p /var/mobile/Documents/.vloc_config.plist

# 实时监控
watch -n 1 'plutil -p /var/mobile/Documents/.vloc_config.plist'
```
