#!/usr/bin/env python3
"""
VirtualLocation IPA Patcher — TrollStore 虚拟定位 dylib 注入器

用法:
    python3 patcher.py <target.ipa> [options]

功能:
    1. 解包目标 IPA
    2. 将 VirtualLocation.dylib 注入目标 App 的 Mach-O 可执行文件
    3. 添加 LC_LOAD_DYLIB load command
    4. 修改 Info.plist 添加必要权限
    5. 使用 ldid 伪签名
    6. 重新打包为可安装的 IPA

依赖:
    - Python 3.7+
    - ldid (brew install ldid)
    - insert_dylib (可选，自带 Mach-O 解析回退)

原理:
    TrollStore 利用 CoreTrust 漏洞绕过签名验证，因此被修改的 IPA
    即使签名无效也能正常安装和运行。我们利用这点注入 dylib。
"""

import os
import sys
import shutil
import struct
import zipfile
import tempfile
import subprocess
import plistlib
import hashlib
from pathlib import Path
from typing import Optional, List, Tuple

# ============================================================
#  配置
# ============================================================

VERSION = "1.0.0"
DYLIB_NAME = "VirtualLocation.dylib"
DYLIB_INSTALL_NAME = f"@executable_path/{DYLIB_NAME}"

# TrollStore 常见 entitlements
TS_ENTITLEMENTS = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>platform-application</key>
    <true/>
    <key>com.apple.private.skip-library-validation</key>
    <true/>
    <key>dynamic-codesigning</key>
    <true/>
    <key>get-task-allow</key>
    <true/>
</dict>
</plist>
"""

# ============================================================
#  Mach-O 解析（回退方案，当 insert_dylib 不可用时）
# ============================================================

class MachO:
    """Mach-O 64-bit 解析器"""

    FAT_MAGIC = 0xcafebabe
    FAT_CIGAM = 0xbebafeca
    MH_MAGIC_64 = 0xfeedfacf
    MH_CIGAM_64 = 0xcffaedfe

    LC_REQ_DYLD = 0x80000000
    LC_SEGMENT_64 = 0x19
    LC_SYMTAB = 0x02
    LC_DYSYMTAB = 0x0b
    LC_LOAD_DYLIB = 0x0c
    LC_ID_DYLIB = 0x0d
    LC_LOAD_WEAK_DYLIB = 0x18 | LC_REQ_DYLD
    LC_REEXPORT_DYLIB = 0x1f | LC_REQ_DYLD
    LC_MAIN = 0x28 | LC_REQ_DYLD
    LC_CODE_SIGNATURE = 0x1d

    def __init__(self, data: bytes):
        self.data = bytearray(data)

    @classmethod
    def from_file(cls, path: str) -> 'MachO':
        with open(path, 'rb') as f:
            return cls(f.read())

    @property
    def magic(self) -> int:
        return struct.unpack_from('<I', self.data, 0)[0]

    @property
    def is_fat(self) -> bool:
        return self.magic in (self.FAT_MAGIC, self.FAT_CIGAM)

    @property
    def is_64(self) -> bool:
        return self.magic in (self.MH_MAGIC_64, self.MH_CIGAM_64)

    def extract_arm64(self) -> Optional['MachO']:
        """从 Fat binary 中提取 arm64 slice"""
        if not self.is_fat:
            return self if self.is_64 else None

        # Fat header: magic(4) + nfat_arch(4)
        nfat = struct.unpack_from('>I', self.data, 4)[0]
        offset = 8

        for i in range(nfat):
            # fat_arch: cputype(4) + cpusubtype(4) + offset(4) + size(4) + align(4)
            cputype, cpusubtype, arch_off, arch_size, align = struct.unpack_from(
                '>IIIII', self.data, offset
            )
            # CPU_TYPE_ARM64 = 0x0100000c, CPU_SUBTYPE_ARM64_ALL = 0
            if cputype == 0x0100000c:
                return MachO(bytes(self.data[arch_off:arch_off + arch_size]))
            offset += 20

        return None

    def inject_dylib(self, dylib_path: str, weak: bool = False) -> bool:
        """注入 LC_LOAD_DYLIB load command"""
        mach = self.extract_arm64()
        if mach is None:
            print("❌ 未找到 arm64 slice")
            return False

        header_size = 32  # mach_header_64
        ncmds = struct.unpack_from('<I', mach.data, 16)[0]
        sizeofcmds = struct.unpack_from('<I', mach.data, 20)[0]

        # 计算对齐后的 dylib path 大小
        dylib_path_bytes = dylib_path.encode('utf-8') + b'\x00'
        # dylib_command = cmd(4) + cmdsize(4) + dylib.name_offset(4) + timestamp(4)
        #                 + current_version(4) + compatibility_version(4)
        header_part = 24
        # name_offset is always 24 (points right after the dylib_command struct)
        # Align cmdsize to 8 bytes
        aligned_path_size = (header_part + len(dylib_path_bytes) + 7) & ~7
        lc_type = self.LC_LOAD_WEAK_DYLIB if weak else self.LC_LOAD_DYLIB

        new_cmd = struct.pack('<II', lc_type, aligned_path_size)
        new_cmd += struct.pack('<III', 24, 2, 1, 1)  # name_offset=24, timestamp=2, current=1, compat=1
        new_cmd += dylib_path_bytes
        # Pad to alignment
        new_cmd += b'\x00' * (aligned_path_size - len(new_cmd))

        # 插入新的 load command（在 LC_CODE_SIGNATURE 之前或末尾）
        insert_offset = header_size + sizeofcmds

        # 更新 mach_header_64
        new_ncmds = ncmds + 1
        new_sizeofcmds = sizeofcmds + aligned_path_size

        # 构建新的 Mach-O
        new_data = bytearray(mach.data[:16])
        new_data += struct.pack('<II', new_ncmds, new_sizeofcmds)
        new_data += mach.data[24:insert_offset]
        new_data += new_cmd
        new_data += mach.data[insert_offset:]

        # 如果原来是 fat binary，需要重建 fat header
        if self.is_fat:
            result = self._rebuild_fat(self.data, bytes(new_data))
        else:
            result = bytes(new_data)

        self.data = bytearray(result)
        return True

    def _rebuild_fat(self, original_fat: bytes, new_arm64: bytes) -> bytes:
        """重建 fat binary，替换 arm64 slice"""
        nfat = struct.unpack_from('>I', original_fat, 4)[0]
        fat_header = bytearray(original_fat[:8 + nfat * 20])

        offset = 8
        arch_entries = []
        total_size = 8 + nfat * 20
        # Align to page size (4096)
        total_size = (total_size + 4095) & ~4095

        for i in range(nfat):
            entry = struct.unpack_from('>IIIII', original_fat, offset)
            arch_entries.append(entry)
            offset += 20

        new_fat_data = bytearray(total_size)
        new_fat_data[:len(fat_header)] = fat_header

        current_offset = total_size
        for i, (cputype, cpusubtype, _, _, align) in enumerate(arch_entries):
            if cputype == 0x0100000c:
                slice_data = new_arm64
            else:
                # 保留原始 slice
                orig_off = struct.unpack_from('>I', original_fat, 8 + i * 20 + 8)[0]
                orig_size = struct.unpack_from('>I', original_fat, 8 + i * 20 + 12)[0]
                slice_data = original_fat[orig_off:orig_off + orig_size]

            # Align
            aligned_offset = (current_offset + align - 1) & ~(align - 1)
            padding = aligned_offset - current_offset
            if padding > 0:
                new_fat_data += b'\x00' * padding

            new_fat_data[current_offset:current_offset] = slice_data

            # Update fat_arch entry
            struct.pack_into('>I', new_fat_data, 8 + i * 20 + 8, current_offset)
            struct.pack_into('>I', new_fat_data, 8 + i * 20 + 12, len(slice_data))

            current_offset += len(slice_data)

        return bytes(new_fat_data)

    def save(self, path: str):
        with open(path, 'wb') as f:
            f.write(bytes(self.data))

    def get_load_commands(self) -> List[Tuple[int, int]]:
        """返回 [(cmd_type, cmdsize), ...]"""
        mach = self.extract_arm64()
        if mach is None:
            return []

        ncmds = struct.unpack_from('<I', mach.data, 16)[0]
        cmds = []
        offset = 32  # sizeof mach_header_64
        for _ in range(ncmds):
            cmd, cmdsize = struct.unpack_from('<II', mach.data, offset)
            cmds.append((cmd, cmdsize))
            offset += cmdsize
        return cmds


# ============================================================
#  IPA Patcher
# ============================================================

class IPAPatcher:
    def __init__(self, ipa_path: str, dylib_path: str,
                 output_path: Optional[str] = None,
                 verbose: bool = True):
        self.ipa_path = Path(ipa_path).resolve()
        self.dylib_path = Path(dylib_path).resolve()
        self.output_path = Path(output_path) if output_path else None
        self.verbose = verbose
        self.temp_dir = None

    def log(self, msg: str):
        if self.verbose:
            print(msg)

    def patch(self) -> Optional[str]:
        """执行完整的注入流程，返回输出 IPA 路径"""
        if not self.ipa_path.exists():
            print(f"❌ IPA 不存在: {self.ipa_path}")
            return None
        if not self.dylib_path.exists():
            print(f"❌ Dylib 不存在: {self.dylib_path}")
            return None

        print("=" * 60)
        print("  VirtualLocation IPA Patcher v" + VERSION)
        print("  TrollStore 虚拟定位 dylib 注入器")
        print("=" * 60)

        # Step 1: 解包
        self.temp_dir = tempfile.mkdtemp(prefix="vloc_patch_")
        self.log(f"\n📦 解包 IPA → {self.temp_dir}")
        self._unzip_ipa()

        # Step 2: 找到 .app bundle
        app_dir = self._find_app_dir()
        if not app_dir:
            print("❌ 未找到 .app bundle")
            return None
        self.log(f"   App Bundle: {app_dir.name}")

        # Step 3: 找到主可执行文件
        executable = self._find_executable(app_dir)
        if not executable:
            print("❌ 未找到 Mach-O 可执行文件")
            return None
        self.log(f"   可执行文件: {executable.name}")

        # Step 4: 注入 dylib
        self.log(f"\n💉 注入 {DYLIB_NAME} → {executable.name}")
        if not self._inject_dylib(executable):
            return None

        # Step 5: 复制 dylib 到 .app bundle
        self.log(f"\n📋 复制 dylib → {app_dir.name}")
        dest_dylib = app_dir / DYLIB_NAME
        shutil.copy2(str(self.dylib_path), str(dest_dylib))
        self.log(f"   ✅ {DYLIB_NAME} 已复制")

        # Step 6: 修改 Info.plist（添加必要权限）
        self.log(f"\n🔧 修改 Info.plist")
        self._patch_info_plist(app_dir)

        # Step 7: 重新签名
        self.log(f"\n✍️  伪签名（ldid）...")
        self._resign(app_dir)

        # Step 8: 打包 IPA
        output = self.output_path or self._default_output_path()
        self.log(f"\n📦 打包 IPA → {output}")
        self._create_ipa(output)

        # Step 9: 清理
        self._cleanup()

        self.log(f"\n{'=' * 60}")
        self.log(f"  ✅ 注入完成！")
        self.log(f"  输出: {output}")
        self.log(f"  用 TrollStore 安装此 IPA 即可")
        self.log(f"{'=' * 60}")

        return str(output)

    def _unzip_ipa(self):
        with zipfile.ZipFile(str(self.ipa_path), 'r') as zf:
            zf.extractall(self.temp_dir)

    def _find_app_dir(self) -> Optional[Path]:
        payload = Path(self.temp_dir) / "Payload"
        if payload.exists():
            for item in payload.iterdir():
                if item.suffix == '.app' and item.is_dir():
                    return item
        # 也搜索根目录
        for item in Path(self.temp_dir).iterdir():
            if item.suffix == '.app' and item.is_dir():
                return item
        return None

    def _find_executable(self, app_dir: Path) -> Optional[Path]:
        """从 Info.plist 读取 CFBundleExecutable"""
        plist_path = app_dir / "Info.plist"
        if not plist_path.exists():
            return None

        with open(plist_path, 'rb') as f:
            plist = plistlib.load(f)

        exec_name = plist.get('CFBundleExecutable', '')
        if not exec_name:
            return None

        exec_path = app_dir / exec_name
        if exec_path.exists():
            return exec_path
        return None

    def _inject_dylib(self, executable: Path) -> bool:
        """注入 LC_LOAD_DYLIB"""
        # 方案 A: 使用 insert_dylib（推荐）
        if shutil.which('insert_dylib'):
            self.log("   使用 insert_dylib...")
            result = subprocess.run(
                ['insert_dylib', '--strip-codesig', '--all-yes',
                 DYLIB_INSTALL_NAME, str(executable), str(executable)],
                capture_output=True, text=True
            )
            if result.returncode == 0:
                self.log("   ✅ insert_dylib 成功")
                return True
            else:
                self.log(f"   ⚠️ insert_dylib 失败: {result.stderr}")
                self.log("   回退到内置 Mach-O 解析器...")
        else:
            self.log("   insert_dylib 未安装，使用内置 Mach-O 解析器...")
            self.log("   建议安装: brew install insert_dylib")

        # 方案 B: 内置 Mach-O 解析器
        try:
            macho = MachO.from_file(str(executable))

            # 检查是否已经注入
            cmds = macho.get_load_commands()
            dylib_cmds = [c for c in cmds if c[0] in
                          (MachO.LC_LOAD_DYLIB, MachO.LC_LOAD_WEAK_DYLIB)]
            self.log(f"   已有 {len(dylib_cmds)} 个 dylib load commands")

            if macho.inject_dylib(DYLIB_INSTALL_NAME):
                macho.save(str(executable))
                self.log("   ✅ 内置解析器注入成功")
                return True
            else:
                self.log("   ❌ 内置解析器注入失败")
                return False
        except Exception as e:
            self.log(f"   ❌ 注入异常: {e}")
            return False

    def _patch_info_plist(self, app_dir: Path):
        """修改 Info.plist"""
        plist_path = app_dir / "Info.plist"
        if not plist_path.exists():
            return

        with open(plist_path, 'rb') as f:
            plist = plistlib.load(f)

        # 添加必要的键
        modified = False

        # 确保 UIFileSharingEnabled
        if 'UIFileSharingEnabled' not in plist:
            plist['UIFileSharingEnabled'] = True
            modified = True

        # 确保支持后台定位
        bg_modes = plist.get('UIBackgroundModes', [])
        if 'location' not in bg_modes:
            if isinstance(bg_modes, list):
                bg_modes.append('location')
            else:
                bg_modes = ['location']
            plist['UIBackgroundModes'] = bg_modes
            modified = True

        # 确保有定位权限描述
        if 'NSLocationWhenInUseUsageDescription' not in plist:
            plist['NSLocationWhenInUseUsageDescription'] = '此应用需要访问位置信息'
            modified = True
        if 'NSLocationAlwaysAndWhenInUseUsageDescription' not in plist:
            plist['NSLocationAlwaysAndWhenInUseUsageDescription'] = '此应用需要持续访问位置信息'
            modified = True

        if modified:
            # 备份
            bak_path = plist_path.with_suffix('.plist.bak')
            shutil.copy2(str(plist_path), str(bak_path))

            with open(plist_path, 'wb') as f:
                plistlib.dump(plist, f)
            self.log("   ✅ Info.plist 已更新")

            # 清理备份
            bak_path.unlink()

    def _resign(self, app_dir: Path):
        """使用 ldid 伪签名"""
        # 先签名 dylib
        dylib = app_dir / DYLIB_NAME
        if dylib.exists():
            if shutil.which('ldid'):
                subprocess.run(['ldid', '-S', str(dylib)],
                              capture_output=True)
                self.log(f"   ✅ ldid 签名: {DYLIB_NAME}")

        # 签名所有 framework 和 dylib
        for item in sorted(app_dir.rglob('*')):
            if item.is_file():
                name = item.name.lower()
                if name.endswith('.dylib') or name.endswith('.framework'):
                    if shutil.which('ldid'):
                        subprocess.run(['ldid', '-S', str(item)],
                                      capture_output=True)

        # 写入 entitlements
        ent_path = app_dir / "entitlements.plist"
        ent_path.write_text(TS_ENTITLEMENTS)

        # 签名主应用
        if shutil.which('ldid'):
            result = subprocess.run(
                ['ldid', '-S' + str(ent_path), str(app_dir)],
                capture_output=True, text=True
            )
            if result.returncode == 0:
                self.log(f"   ✅ ldid 签名: {app_dir.name}")
            else:
                self.log(f"   ⚠️ ldid 签名警告: {result.stderr.strip()}")
        else:
            self.log("   ⚠️ ldid 未安装，跳过签名")
            self.log("   安装: brew install ldid")

        # 清理
        ent_path.unlink(missing_ok=True)

    def _create_ipa(self, output: Path):
        """创建 IPA（本质是 zip）"""
        payload_dir = Path(self.temp_dir) / "Payload"
        if not payload_dir.exists():
            # 创建 Payload 结构
            payload_dir.mkdir(parents=True, exist_ok=True)
            for item in Path(self.temp_dir).iterdir():
                if item.suffix == '.app':
                    shutil.move(str(item), str(payload_dir / item.name))

        with zipfile.ZipFile(str(output), 'w', zipfile.ZIP_DEFLATED) as zf:
            for root, dirs, files in os.walk(self.temp_dir):
                for file in files:
                    file_path = Path(root) / file
                    arcname = file_path.relative_to(self.temp_dir)
                    zf.write(str(file_path), str(arcname))

        # 计算 hash
        sha = hashlib.sha256(output.read_bytes()).hexdigest()[:16]
        self.log(f"   SHA256: {sha}")

    def _default_output_path(self) -> Path:
        stem = self.ipa_path.stem
        return self.ipa_path.parent / f"{stem}_patched.ipa"

    def _cleanup(self):
        if self.temp_dir and Path(self.temp_dir).exists():
            shutil.rmtree(self.temp_dir, ignore_errors=True)


# ============================================================
#  命令行接口
# ============================================================

def main():
    import argparse

    parser = argparse.ArgumentParser(
        description='VirtualLocation IPA Patcher — 注入虚拟定位 dylib 到目标 IPA',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  python3 patcher.py WeChat.ipa
  python3 patcher.py DingTalk.ipa -o DingTalk_patched.ipa
  python3 patcher.py target.ipa --dylib ./output/VirtualLocation.dylib
  python3 patcher.py target.ipa --dry-run    # 仅检查不修改
        """
    )

    parser.add_argument('ipa', help='目标 IPA 文件路径')
    parser.add_argument('-o', '--output', help='输出 IPA 路径（默认: 原文件名_patched.ipa）')
    parser.add_argument('--dylib', default=None,
                        help=f'VirtualLocation.dylib 路径（默认自动搜索）')
    parser.add_argument('-q', '--quiet', action='store_true', help='安静模式')
    parser.add_argument('--dry-run', action='store_true', help='仅分析不修改')
    parser.add_argument('--version', action='version', version=f'v{VERSION}')

    args = parser.parse_args()

    # 查找 dylib
    dylib_path = args.dylib
    if not dylib_path:
        # 自动搜索
        script_dir = Path(__file__).parent.resolve()
        candidates = [
            script_dir.parent / "output" / DYLIB_NAME,
            script_dir.parent / "build" / DYLIB_NAME,
            script_dir.parent / DYLIB_NAME,
            Path.cwd() / DYLIB_NAME,
            Path.cwd() / "output" / DYLIB_NAME,
        ]
        for c in candidates:
            if c.exists():
                dylib_path = str(c)
                break

    if not dylib_path or not Path(dylib_path).exists():
        print(f"❌ 找不到 {DYLIB_NAME}")
        print("   请先用 build_dylib.sh 构建，或用 --dylib 指定路径")
        sys.exit(1)

    # Dry run
    if args.dry_run:
        print("🔍 Dry Run — 分析目标 IPA...")
        ipa_path = Path(args.ipa)
        if not ipa_path.exists():
            print(f"❌ {args.ipa} 不存在")
            sys.exit(1)

        with zipfile.ZipFile(args.ipa, 'r') as zf:
            app_dirs = [n for n in zf.namelist() if n.endswith('.app/')]
            print(f"   Payload 中的 App: {app_dirs}")

            for app_dir in app_dirs:
                info_plist = app_dir + "Info.plist"
                if info_plist in zf.namelist():
                    plist_data = zf.read(info_plist)
                    plist = plistlib.loads(plist_data)
                    print(f"   Bundle ID: {plist.get('CFBundleIdentifier', '?')}")
                    print(f"   Version: {plist.get('CFBundleShortVersionString', '?')}")
                    print(f"   Executable: {plist.get('CFBundleExecutable', '?')}")
        sys.exit(0)

    # 执行注入
    patcher = IPAPatcher(
        ipa_path=args.ipa,
        dylib_path=dylib_path,
        output_path=args.output,
        verbose=not args.quiet
    )

    result = patcher.patch()
    if result:
        sys.exit(0)
    else:
        sys.exit(1)


if __name__ == '__main__':
    main()
