#!/usr/bin/env python3
"""
plist_deploy.py — 将虚拟定位配置文件部署到 iOS 设备

支持 3 种部署方式:

1. **WiFi HTTP 传输** (无需 iTunes)
   - 在 iOS 设备上打开 Filza → 启用 WebDAV Server
   - 或启动内置 HTTP 服务器 (iOS 端需配合)
   - 最简单：使用 Python 发送 HTTP PUT

2. **SSH 传输** (需要越狱或 TrollStore + SSH)
   - ssh root@ip "cat > /var/mobile/Documents/.vloc_config.plist"

3. **iTunes 文件共享** 引导
   - 提示用户如何通过 iTunes/Finder 复制文件

用法:
    python3 plist_deploy.py deploy                    # 交互式部署
    python3 plist_deploy.py deploy --http 192.168.1.5:8080   # HTTP 方式
    python3 plist_deploy.py deploy --ssh root@192.168.1.5    # SSH 方式
    python3 plist_deploy.py serve                     # 启动本地 HTTP 服务器
    python3 plist_deploy.py generate                  # 仅生成 plist
"""

import os
import sys
import json
import plistlib
import base64
import tempfile
import subprocess
from pathlib import Path
from datetime import datetime
from http.server import HTTPServer, SimpleHTTPRequestHandler


# ============================================================
#  配置
# ============================================================

DEFAULT_COORDS = {
    "enabled": True,
    "latitude": 31.2304,
    "longitude": 121.4737,
    "altitude": 10.0,
    "horizontalAccuracy": 5.0,
    "verticalAccuracy": 5.0,
    "speed": 0.0,
    "course": 0.0,
    "timestamp": datetime.now(),
}

# iOS 上的可能路径
IOS_TARGET_PATHS = [
    "/var/mobile/Documents/.vloc_config.plist",
    "/var/mobile/Library/Caches/.vloc_config.plist",
]

SCRIPT_DIR = Path(__file__).parent.resolve()
CONFIG_FILE = SCRIPT_DIR / ".vloc_config.json"


# ============================================================
#  Plist 生成
# ============================================================

def generate_plist(coords: dict = None) -> bytes:
    """生成 .vloc_config.plist 的 XML 内容"""
    if coords is None:
        coords = load_config()

    plist_dict = {
        "enabled": coords.get("enabled", False),
        "latitude": coords.get("latitude", 31.2304),
        "longitude": coords.get("longitude", 121.4737),
        "altitude": coords.get("altitude", 10.0),
        "horizontalAccuracy": coords.get("horizontalAccuracy", 5.0),
        "verticalAccuracy": coords.get("verticalAccuracy", 5.0),
        "speed": coords.get("speed", 0.0),
        "course": coords.get("course", 0.0),
        "timestamp": datetime.now(),
    }

    return plistlib.dumps(plist_dict, fmt=plistlib.FMT_XML)


def save_config(coords: dict):
    """保存 JSON 配置文件（人类可读）"""
    CONFIG_FILE.write_text(json.dumps(coords, indent=2, ensure_ascii=False),
                           encoding='utf-8')


def load_config() -> dict:
    """加载 JSON 配置文件"""
    if CONFIG_FILE.exists():
        try:
            return json.loads(CONFIG_FILE.read_text(encoding='utf-8'))
        except json.JSONDecodeError:
            pass
    return DEFAULT_COORDS


# ============================================================
#  HTTP 部署
# ============================================================

def deploy_via_http(host: str, port: int, plist_data: bytes):
    """通过 HTTP PUT 部署 plist 到 iOS 设备"""
    import urllib.request

    url = f"http://{host}:{port}/.vloc_config.plist"

    req = urllib.request.Request(url, data=plist_data, method='PUT')
    req.add_header('Content-Type', 'application/octet-stream')

    try:
        resp = urllib.request.urlopen(req, timeout=5)
        print(f"✅ HTTP PUT 成功 ({resp.status})")
        return True
    except Exception as e:
        print(f"⚠️  HTTP PUT 失败: {e}")
        return False


def deploy_via_ssh(ssh_target: str, plist_data: bytes):
    """通过 SSH 部署 plist"""
    # 将 plist base64 编码后通过管道传输
    b64_data = base64.b64encode(plist_data).decode('ascii')

    for target_path in IOS_TARGET_PATHS:
        cmd = f'echo "{b64_data}" | base64 -d > {target_path} && echo "OK: {target_path}"'
        full_cmd = ["ssh", ssh_target, cmd]

        try:
            result = subprocess.run(
                full_cmd, capture_output=True, text=True, timeout=10
            )
            if result.returncode == 0:
                print(f"✅ SSH 部署成功: {result.stdout.strip()}")
                return True
            else:
                print(f"⚠️  SSH 失败 ({target_path}): {result.stderr.strip()}")
        except subprocess.TimeoutExpired:
            print(f"⚠️  SSH 超时: {ssh_target}")
        except FileNotFoundError:
            print("❌ ssh 命令不可用，请安装 OpenSSH 客户端")
            return False

    return False


# ============================================================
#  本地 HTTP 服务器（iOS 设备拉取）
# ============================================================

class PlistHandler(SimpleHTTPRequestHandler):
    """自定义 HTTP Handler，提供 plist 文件下载"""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(SCRIPT_DIR), **kwargs)

    def do_GET(self):
        if self.path == '/' or self.path == '/.vloc_config.plist':
            plist_data = generate_plist()
            self.send_response(200)
            self.send_header('Content-Type', 'application/x-plist')
            self.send_header('Content-Disposition',
                             'attachment; filename=".vloc_config.plist"')
            self.send_header('Content-Length', str(len(plist_data)))
            self.end_headers()
            self.wfile.write(plist_data)
        else:
            super().do_GET()

    def log_message(self, format, *args):
        print(f"[{datetime.now().strftime('%H:%M:%S')}] {args[0]}")


def serve_plist(port: int = 8080):
    """启动 HTTP 服务器，iOS 设备访问此 URL 即可下载 plist"""
    server = HTTPServer(('0.0.0.0', port), PlistHandler)

    # 获取本机 IP
    import socket
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(('8.8.8.8', 80))
        local_ip = s.getsockname()[0]
    except Exception:
        local_ip = '127.0.0.1'
    finally:
        s.close()

    print("=" * 60)
    print("  🌐 VirtualLocation Plist Server")
    print("=" * 60)
    print()
    print("  📱 在 iOS 设备上打开 Safari / Filza")
    print(f"  访问: http://{local_ip}:{port}/.vloc_config.plist")
    print()
    print("  下载后将文件移动到:")
    print(f"    {IOS_TARGET_PATHS[0]}")
    print()
    print("  ⏹  按 Ctrl+C 停止服务器")
    print("=" * 60)
    print()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n👋 服务器已停止")
        server.shutdown()


# ============================================================
#  命令行
# ============================================================

def main():
    import argparse

    parser = argparse.ArgumentParser(
        description='VirtualLocation — plist 配置部署工具',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  python3 plist_deploy.py generate              # 生成 .vloc_config.plist 到当前目录
  python3 plist_deploy.py serve                 # 启动 HTTP 服务器
  python3 plist_deploy.py deploy --ssh root@192.168.1.100    # SSH 部署
  python3 plist_deploy.py deploy --http 192.168.1.100:8080   # HTTP 部署
        """
    )

    subparsers = parser.add_subparsers(dest='command', help='子命令')

    # generate
    gen_parser = subparsers.add_parser('generate', help='生成 plist 到本地文件')
    gen_parser.add_argument('--lat', type=float, default=31.2304, help='纬度')
    gen_parser.add_argument('--lon', type=float, default=121.4737, help='经度')
    gen_parser.add_argument('--alt', type=float, default=10.0, help='海拔')
    gen_parser.add_argument('--enable', action='store_true', default=True,
                            help='启用')
    gen_parser.add_argument('--output', '-o', default=None, help='输出路径')

    # serve
    serve_parser = subparsers.add_parser('serve', help='启动 HTTP 文件服务器')
    serve_parser.add_argument('--port', '-p', type=int, default=8080,
                              help='端口 (默认: 8080)')

    # deploy
    deploy_parser = subparsers.add_parser('deploy', help='部署到 iOS 设备')
    deploy_parser.add_argument('--ssh', default=None, help='SSH 目标 (user@host)')
    deploy_parser.add_argument('--http', default=None, help='HTTP 目标 (host:port)')
    deploy_parser.add_argument('--lat', type=float, default=None, help='纬度')
    deploy_parser.add_argument('--lon', type=float, default=None, help='经度')

    args = parser.parse_args()

    if args.command == 'generate':
        coords = load_config()
        coords['latitude'] = args.lat
        coords['longitude'] = args.lon
        coords['altitude'] = args.alt
        coords['enabled'] = args.enable

        plist_data = generate_plist(coords)
        output_path = args.output or (SCRIPT_DIR / '.vloc_config.plist')

        Path(output_path).write_bytes(plist_data)
        print(f"✅ plist 已生成: {output_path}")
        print(f"   坐标: ({args.lat}, {args.lon})")
        print(f"   已启用: {args.enable}")

    elif args.command == 'serve':
        serve_plist(args.port)

    elif args.command == 'deploy':
        coords = load_config()
        if args.lat is not None:
            coords['latitude'] = args.lat
        if args.lon is not None:
            coords['longitude'] = args.lon

        plist_data = generate_plist(coords)
        success = False

        if args.http:
            host, _, port_str = args.http.partition(':')
            port = int(port_str) if port_str else 8080
            success = deploy_via_http(host, port, plist_data)

        elif args.ssh:
            success = deploy_via_ssh(args.ssh, plist_data)

        else:
            # 交互式
            print("选择部署方式:")
            print("  1) HTTP (需要 iOS 端运行 WebDAV/Filza)")
            print("  2) SSH (需要越狱或 OpenSSH)")
            print("  3) 仅保存到本地文件")

            choice = input("> ").strip()

            if choice == '1':
                target = input("输入 iOS 设备 IP:端口 (如 192.168.1.5:8080): ").strip()
                host, _, port_str = target.partition(':')
                port = int(port_str) if port_str else 8080
                success = deploy_via_http(host, port, plist_data)

            elif choice == '2':
                target = input("SSH 目标 (如 root@192.168.1.5): ").strip()
                success = deploy_via_ssh(target, plist_data)

            else:
                output = SCRIPT_DIR / '.vloc_config.plist'
                output.write_bytes(plist_data)
                print(f"✅ 已保存到: {output}")
                print("   请手动复制到 iOS 设备的:")
                for p in IOS_TARGET_PATHS:
                    print(f"     {p}")
                success = True

        if not success:
            print()
            print("💡 备选方案: 启动 HTTP 服务器让 iOS 设备拉取")
            print(f"   python3 plist_deploy.py serve")
            print()
            print("💡 或手动:")
            print(f"   1. 运行: python3 plist_deploy.py generate")
            print(f"   2. 将 .vloc_config.plist 通过 AirDrop / iCloud / 微信 传到 iOS")
            print(f"   3. 在 iOS 上用 Filza 移动到:")
            for p in IOS_TARGET_PATHS:
                print(f"      {p}")

    else:
        parser.print_help()
        sys.exit(1)


if __name__ == '__main__':
    main()
