#!/usr/bin/env python3
"""
VirtualLocation 坐标管理器 — Windows 版
=========================================

Windows 上的虚拟定位坐标管理工具。
无需 macOS，无需 Xcode，纯 Python + tkinter（Windows 自带）。

功能:
  - 预设位置列表（一键选择）
  - 手动坐标输入（度分秒 / 十进制）
  - 参数调节（精度、海拔、速度）
  - 生成 .vloc_config.plist
  - 内置地图选点（打开浏览器）
  - WiFi 部署到 iOS 设备

用法:
  python vloc_win.py
"""

import os
import sys
import json
import shutil
import hashlib
import plistlib
import webbrowser
import http.server
import socketserver
import threading
from pathlib import Path
from datetime import datetime
from typing import Optional

# ============================================================
#  tkinter 导入
# ============================================================

try:
    import tkinter as tk
    from tkinter import ttk, messagebox, filedialog, simpledialog
except ImportError:
    print("❌ tkinter 未安装（通常 Windows Python 自带）")
    sys.exit(1)

# ============================================================
#  预设位置
# ============================================================

PRESETS = [
    {"name": "🏠 上海·外滩",        "lat": 31.2304,  "lon": 121.4737, "alt": 10},
    {"name": "🏛 北京·天安门",      "lat": 39.9087,  "lon": 116.3975, "alt": 50},
    {"name": "🗼 深圳·腾讯大厦",    "lat": 22.5408,  "lon": 113.9345, "alt": 15},
    {"name": "🏯 广州·广州塔",      "lat": 23.1065,  "lon": 113.3245, "alt": 20},
    {"name": "🏔 成都·太古里",      "lat": 30.6538,  "lon": 104.0833, "alt": 500},
    {"name": "🌉 杭州·西湖",        "lat": 30.2439,  "lon": 120.1463, "alt": 10},
    {"name": "🌊 厦门·鼓浪屿",      "lat": 24.4479,  "lon": 118.0685, "alt": 5},
    {"name": "🏖 三亚·亚龙湾",      "lat": 18.2236,  "lon": 109.6352, "alt": 5},
    {"name": "🏔 拉萨·布达拉宫",    "lat": 29.6575,  "lon": 91.1172,  "alt": 3650},
    {"name": "🗽 纽约·时代广场",    "lat": 40.7580,  "lon": -73.9855, "alt": 10},
    {"name": "🗼 东京·涩谷",        "lat": 35.6580,  "lon": 139.7016, "alt": 40},
    {"name": "🌍 伦敦·大本钟",      "lat": 51.5007,  "lon": -0.1246,  "alt": 10},
]

# ============================================================
#  坐标转换工具
# ============================================================

def wgs84_to_gcj02(lat: float, lon: float) -> tuple:
    """WGS-84 → GCJ-02（火星坐标）"""
    a = 6378245.0
    ee = 0.00669342162296594323
    pi = 3.14159265358979323846

    def transform_lat(x, y):
        ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * abs(x) ** 0.5
        ret += (20.0 * __import__('math').sin(6.0 * x * pi) + 20.0 * __import__('math').sin(2.0 * x * pi)) * 2.0 / 3.0
        ret += (20.0 * __import__('math').sin(y * pi) + 40.0 * __import__('math').sin(y / 3.0 * pi)) * 2.0 / 3.0
        ret += (160.0 * __import__('math').sin(y / 12.0 * pi) + 320.0 * __import__('math').sin(y * pi / 30.0)) * 2.0 / 3.0
        return ret

    def transform_lon(x, y):
        ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * abs(x) ** 0.5
        ret += (20.0 * __import__('math').sin(6.0 * x * pi) + 20.0 * __import__('math').sin(2.0 * x * pi)) * 2.0 / 3.0
        ret += (20.0 * __import__('math').sin(x * pi) + 40.0 * __import__('math').sin(x / 3.0 * pi)) * 2.0 / 3.0
        ret += (150.0 * __import__('math').sin(x / 12.0 * pi) + 300.0 * __import__('math').sin(x / 30.0 * pi)) * 2.0 / 3.0
        return ret

    import math
    d_lat = transform_lat(lon - 105.0, lat - 35.0)
    d_lon = transform_lon(lon - 105.0, lat - 35.0)
    rad_lat = lat / 180.0 * pi
    magic = math.sin(rad_lat)
    magic = 1 - ee * magic * magic
    sqrt_magic = math.sqrt(magic)
    d_lat = (d_lat * 180.0) / ((a * (1 - ee)) / (magic * sqrt_magic) * pi)
    d_lon = (d_lon * 180.0) / (a / sqrt_magic * math.cos(rad_lat) * pi)
    return (lat + d_lat, lon + d_lon)

def gcj02_to_wgs84(lat: float, lon: float) -> tuple:
    """GCJ-02 → WGS-84"""
    g_lat, g_lon = wgs84_to_gcj02(lat, lon)
    return (lat * 2 - g_lat, lon * 2 - g_lon)

def dms_to_decimal(d: int, m: int, s: float) -> float:
    """度分秒 → 十进制"""
    return d + m / 60.0 + s / 3600.0

def decimal_to_dms(deg: float) -> tuple:
    """十进制 → 度分秒"""
    d = int(deg)
    mf = (abs(deg) - abs(d)) * 60.0
    m = int(mf)
    s = (mf - m) * 60.0
    return (d, m, s)

# ============================================================
#  主 GUI 类
# ============================================================

class VirtualLocationApp:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("VirtualLocation — 虚拟定位管理器")
        self.root.geometry("680x580")
        self.root.resizable(True, True)

        # 设置图标 (可选)
        try:
            self.root.iconbitmap(default='')
        except:
            pass

        # 配置
        self.config = {
            "enabled": False,
            "latitude": 31.2304,
            "longitude": 121.4737,
            "altitude": 10.0,
            "horizontalAccuracy": 5.0,
            "verticalAccuracy": 5.0,
            "speed": 0.0,
            "course": 0.0,
            "timestamp": 0,
        }

        # iOS 设备 IP（用于部署）
        self.ios_ip = tk.StringVar(value="172.20.10.1")
        self.ios_port = tk.StringVar(value="8080")

        self._build_ui()
        self._update_display()

    # ============================================================
    #  UI 构建
    # ============================================================

    def _build_ui(self):
        # 主容器
        main_frame = ttk.Frame(self.root, padding=10)
        main_frame.pack(fill=tk.BOTH, expand=True)

        # ===== 左侧面板：预设 + 坐标 =====
        left_frame = ttk.LabelFrame(main_frame, text="位置设置", padding=8)
        left_frame.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(0, 5))

        # 预设列表
        ttk.Label(left_frame, text="预设位置:", font=("", 9, "bold")).pack(anchor=tk.W)

        preset_frame = ttk.Frame(left_frame)
        preset_frame.pack(fill=tk.BOTH, expand=True, pady=(5, 10))

        scrollbar = ttk.Scrollbar(preset_frame)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)

        self.preset_listbox = tk.Listbox(
            preset_frame,
            yscrollcommand=scrollbar.set,
            height=8,
            font=("Consolas", 10),
            activestyle='none',
        )
        self.preset_listbox.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.config(command=self.preset_listbox.yview)

        for p in PRESETS:
            self.preset_listbox.insert(tk.END, p["name"])
        self.preset_listbox.bind('<<ListboxSelect>>', self._on_preset_select)

        # 快速选择按钮
        btn_frame = ttk.Frame(left_frame)
        btn_frame.pack(fill=tk.X, pady=(0, 10))

        ttk.Button(btn_frame, text="应用选中", command=self._apply_preset).pack(
            side=tk.LEFT, padx=(0, 5))
        ttk.Button(btn_frame, text="🌐 地图选点", command=self._open_map).pack(
            side=tk.LEFT, padx=(0, 5))
        ttk.Button(btn_frame, text="➕ 添加当前为预设", command=self._add_current_preset).pack(
            side=tk.LEFT)

        # 坐标输入（十进制）
        coord_frame = ttk.LabelFrame(left_frame, text="坐标（十进制）", padding=5)
        coord_frame.pack(fill=tk.X, pady=(0, 10))

        grid = ttk.Frame(coord_frame)
        grid.pack(fill=tk.X)

        ttk.Label(grid, text="纬度:").grid(row=0, column=0, sticky=tk.W, padx=(0, 5))
        self.lat_var = tk.StringVar(value="31.2304")
        self.lat_entry = ttk.Entry(grid, textvariable=self.lat_var, width=14, font=("Consolas", 11))
        self.lat_entry.grid(row=0, column=1, padx=(0, 10))
        self.lat_entry.bind('<KeyRelease>', self._on_coord_change)

        ttk.Label(grid, text="经度:").grid(row=0, column=2, sticky=tk.W, padx=(0, 5))
        self.lon_var = tk.StringVar(value="121.4737")
        self.lon_entry = ttk.Entry(grid, textvariable=self.lon_var, width=14, font=("Consolas", 11))
        self.lon_entry.grid(row=0, column=3, padx=(0, 5))
        self.lon_entry.bind('<KeyRelease>', self._on_coord_change)

        # DMS 格式显示
        self.dms_label = ttk.Label(grid, text="", font=("Consolas", 8), foreground="gray")
        self.dms_label.grid(row=1, column=0, columnspan=4, sticky=tk.W, pady=(3, 0))

        # 坐标转换按钮
        conv_frame = ttk.Frame(coord_frame)
        conv_frame.pack(fill=tk.X, pady=(5, 0))

        ttk.Button(conv_frame, text="→ GCJ-02 (火星)", command=self._to_gcj02).pack(side=tk.LEFT, padx=(0, 5))
        ttk.Button(conv_frame, text="→ WGS-84", command=self._to_wgs84).pack(side=tk.LEFT, padx=(0, 5))
        ttk.Button(conv_frame, text="粘贴坐标", command=self._paste_coord).pack(side=tk.LEFT)

        # 精度/海拔参数
        param_frame = ttk.LabelFrame(left_frame, text="定位参数", padding=5)
        param_frame.pack(fill=tk.X, pady=(0, 10))

        params = [
            ("海拔 (m):", "altitude", 10.0, -500, 9000, 0.5),
            ("水平精度 (m):", "horizontalAccuracy", 5.0, 0, 100, 1),
            ("垂直精度 (m):", "verticalAccuracy", 5.0, 0, 100, 1),
            ("速度 (m/s):", "speed", 0.0, 0, 100, 0.5),
            ("朝向 (°):", "course", 0.0, 0, 360, 1),
        ]

        self.param_vars = {}
        for i, (label, key, default, pmin, pmax, step) in enumerate(params):
            f = ttk.Frame(param_frame)
            f.pack(fill=tk.X, pady=1)
            ttk.Label(f, text=label, width=14).pack(side=tk.LEFT)

            var = tk.DoubleVar(value=default)
            self.param_vars[key] = var

            scale = ttk.Scale(f, from_=pmin, to=pmax, variable=var,
                             orient=tk.HORIZONTAL, length=150)
            scale.pack(side=tk.LEFT, padx=(5, 5))

            val_label = ttk.Label(f, text="", width=8, font=("Consolas", 9))
            val_label.pack(side=tk.LEFT)

            def make_callback(k=key, v=var, vl=val_label):
                def cb(*args):
                    vl.config(text=f"{v.get():.1f}")
                    self.config[k] = v.get()
                return cb

            var.trace_add('write', make_callback())
            # 初始化显示
            val_label.config(text=f"{default:.1f}")

        # ===== 右侧面板：状态 + 操作 =====
        right_frame = ttk.Frame(main_frame)
        right_frame.pack(side=tk.RIGHT, fill=tk.BOTH, padx=(5, 0))

        # 状态显示
        status_frame = ttk.LabelFrame(right_frame, text="状态", padding=8)
        status_frame.pack(fill=tk.X, pady=(0, 10))

        self.status_text = tk.Text(status_frame, height=6, width=30,
                                    font=("Consolas", 10), state=tk.DISABLED,
                                    bg="#1e1e1e", fg="#00ff00", relief=tk.FLAT)
        self.status_text.pack(fill=tk.BOTH)

        # 激活/停用
        self.active_btn = ttk.Button(right_frame, text="🔴 激活虚拟定位",
                                      command=self._toggle_active, style="Accent.TButton")
        self.active_btn.pack(fill=tk.X, pady=(0, 10))

        # 生成 plist
        ttk.Button(right_frame, text="📄 生成 .vloc_config.plist",
                   command=self._generate_plist).pack(fill=tk.X, pady=(0, 5))

        ttk.Button(right_frame, text="💾 保存 plist 到...",
                   command=self._save_plist_dialog).pack(fill=tk.X, pady=(0, 10))

        # 部署到 iOS
        deploy_frame = ttk.LabelFrame(right_frame, text="部署到 iOS", padding=5)
        deploy_frame.pack(fill=tk.X, pady=(0, 10))

        ip_frame = ttk.Frame(deploy_frame)
        ip_frame.pack(fill=tk.X, pady=(0, 5))
        ttk.Label(ip_frame, text="IP:").pack(side=tk.LEFT)
        ttk.Entry(ip_frame, textvariable=self.ios_ip, width=14).pack(side=tk.LEFT, padx=(5, 10))
        ttk.Label(ip_frame, text="端口:").pack(side=tk.LEFT)
        ttk.Entry(ip_frame, textvariable=self.ios_port, width=6).pack(side=tk.LEFT)

        ttk.Button(deploy_frame, text="📡 部署 plist 到设备",
                   command=self._deploy_plist).pack(fill=tk.X, pady=(0, 3))

        ttk.Button(deploy_frame, text="🌐 启动 HTTP 服务器 (设备下载)",
                   command=self._start_http_server).pack(fill=tk.X)

        # 底部工具栏
        bottom_frame = ttk.Frame(right_frame)
        bottom_frame.pack(fill=tk.X, pady=(10, 0))
        ttk.Button(bottom_frame, text="📋 复制坐标", command=self._copy_coord).pack(fill=tk.X, pady=(0, 3))
        ttk.Button(bottom_frame, text="🔄 重置默认", command=self._reset_default).pack(fill=tk.X)

    # ============================================================
    #  事件处理
    # ============================================================

    def _on_preset_select(self, event):
        """预设列表选择事件"""
        sel = self.preset_listbox.curselection()
        if sel:
            p = PRESETS[sel[0]]
            self._update_status(f"已选择: {p['name']}")

    def _apply_preset(self):
        """应用选中的预设"""
        sel = self.preset_listbox.curselection()
        if not sel:
            messagebox.showwarning("提示", "请先在列表中选择一个预设")
            return

        p = PRESETS[sel[0]]
        self.lat_var.set(str(p["lat"]))
        self.lon_var.set(str(p["lon"]))
        self.param_vars["altitude"].set(p.get("alt", 10.0))
        self._sync_config()
        self._update_display()
        self._update_status(f"✅ 已应用预设: {p['name']}")

    def _on_coord_change(self, event=None):
        """坐标输入变化"""
        self._sync_config()
        self._update_display()

    def _sync_config(self):
        """同步 UI → config dict"""
        try:
            self.config["latitude"] = float(self.lat_var.get())
            self.config["longitude"] = float(self.lon_var.get())
        except ValueError:
            pass
        for key, var in self.param_vars.items():
            self.config[key] = var.get()

    def _update_display(self):
        """更新 DMS 显示"""
        try:
            lat = float(self.lat_var.get())
            lon = float(self.lon_var.get())
            lat_dms = decimal_to_dms(lat)
            lon_dms = decimal_to_dms(lon)
            self.dms_label.config(
                text=f"DMS: {lat_dms[0]}°{lat_dms[1]}'{lat_dms[2]:.2f}\"N  "
                     f"{lon_dms[0]}°{lon_dms[1]}'{lon_dms[2]:.2f}\"E"
            )
        except:
            self.dms_label.config(text="DMS: 输入无效")

    def _update_status(self, msg: str):
        """更新状态文本框"""
        self.status_text.config(state=tk.NORMAL)
        self.status_text.insert(tk.END, f"[{datetime.now().strftime('%H:%M:%S')}] {msg}\n")
        self.status_text.see(tk.END)
        self.status_text.config(state=tk.DISABLED)

    def _toggle_active(self):
        """切换激活状态"""
        self.config["enabled"] = not self.config.get("enabled", False)

        if self.config["enabled"]:
            self.active_btn.config(text="🟢 虚拟定位已激活 (点击停用)")
            self._update_status("🟢 虚拟定位已激活")
        else:
            self.active_btn.config(text="🔴 激活虚拟定位")
            self._update_status("🔴 虚拟定位已停用")

    def _generate_plist(self):
        """生成 plist 并显示"""
        self._sync_config()
        plist_path = self._write_plist()
        if plist_path:
            self._update_status(f"✅ plist 已生成: {plist_path}")
            messagebox.showinfo("生成成功",
                f"配置文件已生成:\n{plist_path}\n\n"
                f"将此文件复制到 iOS 设备的:\n"
                f"/var/mobile/Documents/.vloc_config.plist\n\n"
                f"或使用下面的「部署到 iOS」功能通过 WiFi 发送。")

    def _save_plist_dialog(self):
        """另存为对话框"""
        self._sync_config()
        path = filedialog.asksaveasfilename(
            defaultextension=".plist",
            filetypes=[("plist files", "*.plist"), ("all files", "*.*")],
            initialfile=".vloc_config.plist",
        )
        if path:
            self._write_plist(path)
            self._update_status(f"✅ 已保存: {path}")
            messagebox.showinfo("保存成功", f"已保存到:\n{path}")

    def _write_plist(self, path: Optional[str] = None) -> Optional[str]:
        """写入 plist 文件"""
        if path is None:
            path = str(Path.cwd() / ".vloc_config.plist")

        config = dict(self.config)
        if config.get("timestamp", 0) == 0:
            config["timestamp"] = datetime.now()

        plist_data = {
            "enabled": config.get("enabled", False),
            "latitude": config["latitude"],
            "longitude": config["longitude"],
            "altitude": config["altitude"],
            "horizontalAccuracy": config["horizontalAccuracy"],
            "verticalAccuracy": config["verticalAccuracy"],
            "speed": config["speed"],
            "course": config["course"],
            "timestamp": config.get("timestamp", datetime.now()),
        }

        try:
            with open(path, 'wb') as f:
                plistlib.dump(plist_data, f)
            return path
        except Exception as e:
            messagebox.showerror("写入失败", str(e))
            return None

    def _deploy_plist(self):
        """部署 plist 到 iOS 设备（通过 HTTP PUT 或 SSH）"""
        self._sync_config()
        plist_path = self._write_plist()
        if not plist_path:
            return

        ip = self.ios_ip.get().strip()
        port = self.ios_port.get().strip()

        if not ip:
            messagebox.showerror("错误", "请输入 iOS 设备的 IP 地址")
            return

        # 方案 A: 启动 HTTP 服务器让设备下载
        result = messagebox.askyesno(
            "部署方式",
            f"将启动 HTTP 服务器在 {port} 端口。\n\n"
            f"然后在 iOS 设备上用 Safari 访问:\n"
            f"http://{ip}:{port}\n\n"
            f"下载后移动到:\n"
            f"/var/mobile/Documents/.vloc_config.plist\n\n"
            f"是否启动服务器？"
        )
        if result:
            self._start_http_server()

    def _start_http_server(self):
        """启动 HTTP 服务器供 iOS 设备下载 plist"""
        self._sync_config()
        self._write_plist()

        port = int(self.ios_port.get().strip() or "8080")

        # 在独立线程中启动服务器
        class QuietHandler(http.server.SimpleHTTPRequestHandler):
            def log_message(self, format, *args):
                pass  # 安静模式

        def serve():
            try:
                os.chdir(str(Path.cwd()))
                with socketserver.TCPServer(("0.0.0.0", port), QuietHandler) as httpd:
                    self._update_status(f"🌐 HTTP 服务器已启动: http://{self.ios_ip.get().strip()}:{port}")
                    self._update_status(f"   在 iOS 设备浏览器中打开以上地址下载 plist")
                    self._update_status(f"   下载后移动到 /var/mobile/Documents/.vloc_config.plist")
                    httpd.serve_forever()
            except Exception as e:
                self._update_status(f"❌ 服务器启动失败: {e}")

        thread = threading.Thread(target=serve, daemon=True)
        thread.start()

        messagebox.showinfo(
            "HTTP 服务器已启动",
            f"服务器地址: http://{self.ios_ip.get().strip()}:{port}\n\n"
            f"在 iOS 设备上:\n"
            f"1. 用 Safari 打开以上地址\n"
            f"2. 点击 .vloc_config.plist 下载\n"
            f"3. 用 Filza 移动到 /var/mobile/Documents/\n\n"
            f"关闭此窗口后服务器仍在运行，关闭程序时自动停止。"
        )

    def _open_map(self):
        """在浏览器中打开地图选点"""
        try:
            lat = float(self.lat_var.get())
            lon = float(self.lon_var.get())
        except ValueError:
            lat, lon = 31.2304, 121.4737

        # 生成一个本地 HTML 地图
        html = self._generate_map_html(lat, lon)
        map_path = Path.cwd() / "vloc_map.html"
        map_path.write_text(html, encoding='utf-8')

        webbrowser.open(f"file:///{map_path}")
        self._update_status("🌐 地图已在浏览器中打开")

    def _generate_map_html(self, lat: float, lon: float) -> str:
        """生成 Leaflet.js 地图 HTML"""
        return f'''<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8"/>
<title>VirtualLocation 地图选点</title>
<meta name="viewport" content="width=device-width, initial-scale=1.0"/>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"/>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<style>
  body {{ margin:0; padding:0; }}
  #map {{ width:100vw; height:100vh; }}
  .coord-panel {{
    position:absolute; bottom:20px; left:50%; transform:translateX(-50%);
    background:rgba(0,0,0,0.85); color:#0f0; padding:12px 20px;
    border-radius:10px; font-family:monospace; font-size:14px;
    z-index:1000; text-align:center;
    pointer-events:none;
  }}
  .btn-panel {{
    position:absolute; top:10px; right:10px; z-index:1000;
  }}
  button {{
    padding:10px 16px; margin:4px; border:none; border-radius:8px;
    font-size:14px; cursor:pointer; background:#007aff; color:#fff;
  }}
  button.copy {{ background:#34c759; }}
</style>
</head>
<body>
<div id="map"></div>
<div class="coord-panel" id="info">
  纬度: {lat:.6f} | 经度: {lon:.6f}<br>
  点击地图任意位置选取坐标
</div>
<div class="btn-panel">
  <button onclick="copyCoord()" class="copy">📋 复制坐标</button>
  <button onclick="window.close()">✕ 关闭</button>
</div>
<script>
  var map = L.map('map').setView([{lat}, {lon}], 16);
  L.tileLayer('https://{{s}}.tile.openstreetmap.org/{{z}}/{{x}}/{{y}}.png', {{
    attribution: '© OpenStreetMap',
    maxZoom: 19
  }}).addTo(map);

  var marker = L.marker([{lat}, {lon}], {{draggable:true}}).addTo(map);

  function updateInfo(latlng) {{
    document.getElementById('info').innerHTML =
      '纬度: ' + latlng.lat.toFixed(6) + ' | 经度: ' + latlng.lng.toFixed(6) +
      '<br>点击地图任意位置选取坐标';
  }}

  map.on('click', function(e) {{
    marker.setLatLng(e.latlng);
    updateInfo(e.latlng);
  }});

  marker.on('dragend', function(e) {{
    var pos = marker.getLatLng();
    updateInfo(pos);
  }});

  function copyCoord() {{
    var pos = marker.getLatLng();
    var text = pos.lat.toFixed(6) + ', ' + pos.lng.toFixed(6);
    navigator.clipboard.writeText(text).then(function() {{
      alert('已复制: ' + text);
    }});
  }}
</script>
</body>
</html>'''

    def _to_gcj02(self):
        """WGS-84 → GCJ-02 转换"""
        try:
            lat = float(self.lat_var.get())
            lon = float(self.lon_var.get())
            g_lat, g_lon = wgs84_to_gcj02(lat, lon)
            self.lat_var.set(f"{g_lat:.6f}")
            self.lon_var.set(f"{g_lon:.6f}")
            self._sync_config()
            self._update_display()
            self._update_status(f"✅ WGS-84 → GCJ-02: ({g_lat:.6f}, {g_lon:.6f})")
        except ValueError:
            messagebox.showerror("错误", "坐标格式无效")

    def _to_wgs84(self):
        """GCJ-02 → WGS-84 转换"""
        try:
            lat = float(self.lat_var.get())
            lon = float(self.lon_var.get())
            w_lat, w_lon = gcj02_to_wgs84(lat, lon)
            self.lat_var.set(f"{w_lat:.6f}")
            self.lon_var.set(f"{w_lon:.6f}")
            self._sync_config()
            self._update_display()
            self._update_status(f"✅ GCJ-02 → WGS-84: ({w_lat:.6f}, {w_lon:.6f})")
        except ValueError:
            messagebox.showerror("错误", "坐标格式无效")

    def _paste_coord(self):
        """从剪贴板粘贴坐标"""
        try:
            text = self.root.clipboard_get()
            # 支持格式: "31.2304, 121.4737" 或 "31.2304 121.4737" 等
            import re
            nums = re.findall(r'[-+]?\d+\.?\d*', text)
            if len(nums) >= 2:
                self.lat_var.set(nums[0])
                self.lon_var.set(nums[1])
                self._sync_config()
                self._update_display()
                self._update_status(f"✅ 已粘贴坐标: ({nums[0]}, {nums[1]})")
            else:
                messagebox.showwarning("提示", "剪贴板中未检测到坐标格式")
        except:
            messagebox.showerror("错误", "无法读取剪贴板")

    def _add_current_preset(self):
        """将当前坐标添加为预设"""
        try:
            lat = float(self.lat_var.get())
            lon = float(self.lon_var.get())
            alt = self.param_vars["altitude"].get()
        except ValueError:
            messagebox.showerror("错误", "坐标无效")
            return

        name = simpledialog.askstring("添加预设", "预设名称:", parent=self.root)
        if name:
            preset = {"name": name, "lat": lat, "lon": lon, "alt": alt}
            PRESETS.append(preset)
            self.preset_listbox.insert(tk.END, name)
            self._update_status(f"➕ 已添加预设: {name} ({lat}, {lon})")

    def _copy_coord(self):
        """复制坐标到剪贴板"""
        try:
            lat = float(self.lat_var.get())
            lon = float(self.lon_var.get())
            text = f"{lat:.6f}, {lon:.6f}"
            self.root.clipboard_clear()
            self.root.clipboard_append(text)
            self._update_status(f"📋 已复制: {text}")
            messagebox.showinfo("已复制", f"坐标已复制到剪贴板:\n{text}")
        except ValueError:
            messagebox.showerror("错误", "坐标无效")

    def _reset_default(self):
        """重置为默认值"""
        self.lat_var.set("31.2304")
        self.lon_var.set("121.4737")
        self.param_vars["altitude"].set(10.0)
        self.param_vars["horizontalAccuracy"].set(5.0)
        self.param_vars["verticalAccuracy"].set(5.0)
        self.param_vars["speed"].set(0.0)
        self.param_vars["course"].set(0.0)
        self.config["enabled"] = False
        self.active_btn.config(text="🔴 激活虚拟定位")
        self._sync_config()
        self._update_display()
        self._update_status("🔄 已重置为默认值")

    def run(self):
        self.root.mainloop()


# ============================================================
#  入口
# ============================================================

if __name__ == '__main__':
    app = VirtualLocationApp()
    app.run()
