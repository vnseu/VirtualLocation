# 🌍 VirtualLocation — TrollStore 全局虚拟定位工具

> **免越狱 · 全局生效 · 任意 App · 永久签名**

基于 TrollStore（巨魔商店）CoreTrust 漏洞的 iOS 虚拟定位工具。通过 dylib 注入 + CoreLocation Hook，让任意 App 读取到伪造的 GPS 坐标，无需越狱。

---

## 🎯 效果

| 功能 | 说明 |
|------|------|
| **全局虚拟定位** | 注入后的目标 App 所有定位 API 均返回伪造坐标 |
| **地图可视化选点** | SwiftUI MapKit 地图直接长按选点 |
| **一键激活/停用** | 随时开关，停用后恢复正常定位 |
| **预设管理** | 保存常用位置（公司、家、任意城市） |
| **WGS-84 / GCJ-02 / BD-09 坐标转换** | 内置火星坐标和百度坐标互转 |
| **热更新** | 修改坐标后目标 App 无需重启即可生效 |
| **精度/海拔/速度模拟** | 可自定义定位精度、海拔高度、移动速度、朝向 |
| **支持 iOS 14.0 - 16.6.1 / 17.0** | 覆盖 TrollStore 全版本 |

---

## 🏗 架构

```
┌──────────────────────────┐
│  VirtualLocation.app      │  ← TrollStore 安装，选点 + 写配置
│  (SwiftUI + MapKit)       │
└────────┬─────────────────┘
         │ 写入 .vloc_config.plist
         ▼
┌──────────────────────────┐
│  共享配置文件              │  ← /var/mobile/Documents/.vloc_config.plist
│  {enabled, lat, lon, …}   │
└────────┬─────────────────┘
         │ 读取
         ▼
┌──────────────────────────┐
│  VirtualLocation.dylib    │  ← 已注入目标 App 的 Mach-O
│  ┌──────────────────────┐ │
│  │ fishhook (C 函数)     │ │  ← CLLocationCoordinate2DMake
│  │ ObjC Swizzling        │ │  ← CLLocationManager / CLLocation
│  │ Delegate Hook         │ │  ← locationManager:didUpdateLocations:
│  └──────────────────────┘ │
└──────────────────────────┘
         │
         ▼
┌──────────────────────────┐
│  目标 App (微信/钉钉/...)  │  ← 看到伪造的 GPS 坐标
│  所有定位 API → 假定位     │
└──────────────────────────┘
```

## 🔬 Hook 点覆盖

### CLLocationManager（ObjC Method Swizzling）

| 方法 | 行为 |
|------|------|
| `startUpdatingLocation` | 阻止真实 GPS 启动，立即注入假定位回调 |
| `stopUpdatingLocation` | 拦截，不执行（GPS 未实际启动） |
| `requestLocation` | 劫持，返回伪造单次定位 |
| `location` (getter) | 返回 VLocFakeLocation 实例 |
| `setDelegate:` | 拦截 delegate 设置，自动 swizzle 回调方法 |

### CLLocation（ObjC Method Swizzling）

| 属性 | 返回 |
|------|------|
| `coordinate` | 配置的 (lat, lon) |
| `altitude` | 配置的海拔 |
| `horizontalAccuracy` | 配置的水平精度 |
| `verticalAccuracy` | 配置的垂直精度 |
| `speed` | 配置的速度 |
| `course` | 配置的朝向 |
| `timestamp` | 配置的时间戳或当前时间 |

### C 函数（fishhook）

| 函数 | 行为 |
|------|------|
| `CLLocationCoordinate2DMake()` | 替换为配置坐标 |

### Delegate 回调

| 回调方法 | 行为 |
|------|------|
| `locationManager:didUpdateLocations:` | 注入 VLocFakeLocation |
| `locationManager:didUpdateToLocation:fromLocation:` | 注入 VLocFakeLocation |

---

## 📦 项目结构

```
VirtualLocation/
├── Dylib/                         # 注入引擎（C + ObjC）
│   ├── VirtualLocation.h          # 配置结构 + API 声明
│   ├── VirtualLocationLoader.m    # dylib constructor + 热更新监控
│   ├── HookLocation.m             # CoreLocation 全家桶 Hook（核心）
│   ├── ConfigReader.m             # 配置文件读取
│   ├── fishhook.h                 # Facebook fishhook（C 函数 Hook）
│   ├── fishhook.c
│   └── Info.plist
│
├── App/                           # GUI 配置器（SwiftUI）
│   ├── VirtualLocationApp.swift   # App 入口
│   ├── ContentView.swift          # Tab 主界面
│   ├── MapPickerView.swift        # 地图选点
│   ├── LocationViewModel.swift    # 位置状态管理
│   ├── LocationPresetManager.swift # 预设管理
│   ├── PresetListView.swift       # 预设列表 + 编辑
│   ├── SettingsView.swift         # 高级设置 + 坐标转换
│   ├── ConfigWriter.swift         # plist 写入
│   ├── Info.plist
│   └── entitlements.plist         # TrollStore 权限
│
├── Patcher/                       # IPA 注入器（Python）
│   └── patcher.py                 # 解包 → 注入 → 重签 → 打包
│
├── Scripts/                       # macOS 构建脚本
│   ├── build.sh                   # 一键构建
│   ├── build_dylib.sh             # 构建 dylib
│   └── build_app.sh               # 构建 App + IPA
│
├── .github/workflows/             # CI/CD (免 macOS 构建)
│   └── build.yml                  # GitHub Actions 自动构建
│
├── vloc_win.py                    # 🪟 Windows 坐标管理器 (Python GUI)
├── map_picker.html                # 🗺 浏览器地图选点 (Leaflet.js)
├── plist_deploy.py                # 📡 配置部署工具 (HTTP/SSH)
│
├── Makefile
├── README.md                      # 本文档
└── DEVELOPER_MANUAL.md            # 开发者手册
```

---

## 🚀 快速开始

### ⚡ 方式一：Windows 用户（推荐）

> **无需 macOS！** 用 GitHub Actions 免费构建 dylib，Windows 上完成其余操作。

#### 第一步：获取 dylib（二选一）

**A. GitHub Actions 自动构建（推荐）**
1. Fork 此仓库到你的 GitHub
2. 进入 Actions → Build VirtualLocation → Run workflow
3. 等待 ~3 分钟，下载 artifact `VirtualLocation.dylib`

**B. 使用预编译版本**
- 从 [Releases](../../releases) 下载最新的 `VirtualLocation.dylib`

#### 第二步：设置虚拟坐标

```bash
# 🪟 Windows 上运行 GUI 工具
python vloc_win.py
# → 选坐标 → 生成 plist

# 或者命令行快速设置
python plist_deploy.py generate --lat 31.2304 --lon 121.4737 --enable
```

#### 第三步：部署配置到 iOS

```bash
# 方式 A: 启动 HTTP 服务器，iOS 端 Safari 访问下载
python plist_deploy.py serve
# → 在 iOS 上用 Safari 打开显示的 URL
# → 下载后用 Filza 移动到 /var/mobile/Documents/

# 方式 B: SSH 直接部署（需越狱或 OpenSSH）
python plist_deploy.py deploy --ssh root@192.168.1.100

# 方式 C: 手动传文件
# → AirDrop / 微信 / iCloud 把 .vloc_config.plist 传到手机
# → Filza 移动到 /var/mobile/Documents/
```

#### 第四步：注入目标 App

```bash
# Windows Python 直接运行（无需 macOS）
python Patcher/patcher.py 微信.ipa -o 微信_虚拟定位.ipa
```

#### 第五步：安装并使用

1. 将 `微信_虚拟定位.ipa` 用 TrollStore 安装
2. iOS 端安装 `VirtualLocation.ipa`（从 GitHub Actions artifact 下载）
3. 打开 VirtualLocation App → 激活虚拟定位
4. 切换到目标 App → ✅ 定位为假位置

---

### 🍎 方式二：macOS 用户（完整构建）

#### 准备工作

- **macOS** + Xcode Command Line Tools
- **ldid**: `brew install ldid`
- **insert_dylib** (可选，推荐): `brew install insert_dylib`
- **TrollStore** 已安装在目标 iOS 设备上

#### 1. 构建

```bash
cd VirtualLocation
bash Scripts/build.sh

# 产物:
#   output/VirtualLocation.dylib   ← Hook 引擎
#   output/VirtualLocation.ipa     ← 配置器 App
```

#### 2. 安装配置器 App

TrollStore → 点右上角 + → 选择 `output/VirtualLocation.ipa` → Install

#### 3. 注入目标 App

```bash
python3 Patcher/patcher.py 微信.ipa -o 微信_虚拟定位.ipa
```

#### 4. 使用

1. 打开 VirtualLocation App → 地图选点 → 激活
2. 切换目标 App → 假定位生效 ✅

### 6. 停用

- 打开 VirtualLocation App → 点击 **「停用虚拟定位」**
- 或删除配置文件 `/var/mobile/Documents/.vloc_config.plist`

---

## 🪟 Windows 工具详解

### vloc_win.py — 坐标管理 GUI

```bash
python vloc_win.py
```

功能:
- 📋 **预设列表** — 15 个国内外常用位置，一键选择
- 🗺 **地图选点** — 调用浏览器打开 Leaflet.js 交互式地图
- ✏️ **手动输入** — 直接输入经纬度
- 🔄 **坐标转换** — WGS-84 ↔ GCJ-02 ↔ BD-09 三方互转
- 💾 **生成 plist** — 一键生成配置文件
- 📡 **部署到设备** — 通过 HTTP 或 SSH 推送到 iOS

### map_picker.html — 浏览器地图

`vloc_win.py` 会调用此文件在浏览器中打开交互式地图：
- 15 个预设位置标签
- 点击地图选点 / 拖拽标记微调
- 按住 Ctrl 移动地图跟随中心
- 地名搜索（调用 OpenStreetMap API）
- WGS-84 → GCJ-02 火星坐标自动显示

### plist_deploy.py — 配置部署工具

```bash
# 生成 plist 到本地
python plist_deploy.py generate --lat 31.2304 --lon 121.4737

# 启动 HTTP 服务器（iOS 设备拉取）
python plist_deploy.py serve --port 8080

# SSH 直接部署
python plist_deploy.py deploy --ssh root@192.168.1.5

# 交互式部署菜单
python plist_deploy.py deploy
```

---

## 🔧 高级用法

### 仅注入单个 App

```bash
python3 Patcher/patcher.py DingTalk.ipa -o DingTalk_fake.ipa
```

### 批量注入

```bash
for ipa in *.ipa; do
    python3 Patcher/patcher.py "$ipa" -o "patched_${ipa}"
done
```

### Dry Run（不修改，仅分析）

```bash
python3 Patcher/patcher.py target.ipa --dry-run
```

### 指定 dylib 路径

```bash
python3 Patcher/patcher.py target.ipa --dylib ./custom/VirtualLocation.dylib
```

---

## 🛡 技术原理详解

### TrollStore 为什么能做到？

1. **CoreTrust 漏洞**：iOS 的代码签名验证链存在缺陷，特制的证书链可以绕过签名检查
2. **任意 Entitlement**：TrollStore 安装的 App 可以使用任意 entitlement，包括 `platform-application`、`com.apple.private.skip-library-validation` 等
3. **无沙盒限制**：通过 `com.apple.private.security.no-sandbox` 可以访问全文件系统

### dylib 注入原理

1. 修改目标 App 的 Mach-O 可执行文件，添加 `LC_LOAD_DYLIB` load command
2. 指向 `@executable_path/VirtualLocation.dylib`
3. iOS 动态链接器在加载 App 时自动加载 dylib
4. dylib 的 `__attribute__((constructor))` 在 `main()` 之前执行 Hook 安装

### Hook 原理

```
┌─ C 函数 ──────────────────────────────────┐
│ fishhook                                   │
│ 修改 __DATA 段的 lazy/non-lazy symbol ptr  │
│ CLLocationCoordinate2DMake → 替换实现      │
└────────────────────────────────────────────┘

┌─ ObjC 方法 ────────────────────────────────┐
│ Method Swizzling                            │
│ class_getInstanceMethod + method_setImpl    │
│ CLLocationManager.startUpdatingLocation    │
│ → 替换为 block + delegate 注入              │
└─────────────────────────────────────────────┘
```

### 配置文件格式

```xml
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
    <key>enabled</key>              <true/>
    <key>latitude</key>             <real>31.2304</real>
    <key>longitude</key>            <real>121.4737</real>
    <key>altitude</key>             <real>10.0</real>
    <key>horizontalAccuracy</key>   <real>5.0</real>
    <key>verticalAccuracy</key>     <real>5.0</real>
    <key>speed</key>                <real>0.0</real>
    <key>course</key>               <real>0.0</real>
    <key>timestamp</key>            <date>2024-01-01T00:00:00Z</date>
</dict>
</plist>
```

---

## ⚠️ 注意事项

| 项目 | 说明 |
|------|------|
| **iOS 版本** | iOS 14.0 - 16.6.1（部分设备支持 17.0），iOS 17.0.1+ 不可用 |
| **TrollStore** | 必须先安装 TrollStore |
| **数据保留** | 注入后的 IPA 安装会覆盖原 App，但**用户数据不丢失** |
| **App 更新** | 目标 App 更新后需重新注入 |
| **越狱检测** | 某些 App 有越狱/TrollStore 检测，可能需要额外处理 |
| **企业 App** | 企业签名 App 同样适用 |

---

## 📋 兼容性

| 项目 | 支持 |
|------|------|
| **iOS 版本** | 14.0 / 14.x / 15.0 - 15.4.1 / 15.5 - 16.5 / 16.5.1 - 16.6.1 / 17.0 |
| **设备** | arm64 (iPhone 6s 及以上) |
| **TrollStore 版本** | 1.x / 2.x |
| **架构** | arm64 only |

---

## 🛠 故障排除

### dylib 未加载

```bash
# 检查是否注入了 LC_LOAD_DYLIB
python3 Patcher/patcher.py target.ipa --dry-run
otool -L Payload/Target.app/Target | grep VirtualLocation
```

### 定位未被 Hook

- 确认 VirtualLocation App 中「激活」按钮已点击（绿色）
- 检查配置文件是否存在：Filza 打开 `/var/mobile/Documents/.vloc_config.plist`
- 查看目标 App 日志：Xcode → Devices → View Device Logs → 搜索 "VirtualLocation"

### App 闪退

```
可能原因:
1. insert_dylib 破坏了 Mach-O 结构 → 改用内置解析器
2. dylib 依赖缺失 → 确保 dylib 是 arm64
3. 签名问题 → 重新 ldid 签名
```

---

## 📄 License

MIT — 仅供学习和安全研究使用，请遵守当地法律法规。

---

## 🙏 致谢

- [TrollStore](https://github.com/opa334/TrollStore) — opa334
- [fishhook](https://github.com/facebook/fishhook) — Facebook
- [insert_dylib](https://github.com/Tyilo/insert_dylib) — Tyilo
- [ldid](https://github.com/ProcursusTeam/ldid) — ProcursusTeam
