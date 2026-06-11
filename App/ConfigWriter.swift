//
//  ConfigWriter.swift
//  将虚拟定位配置写入共享 plist 文件
//  同时写入多个路径以确保 dylib 能读取到
//

import Foundation

class ConfigWriter {

    private let configFileName = ".vloc_config.plist"

    // 写入路径（优先级从高到低）
    var targetPaths: [String] {
        var paths: [String] = []

        // /var/mobile/Documents（最通用）
        paths.append("/var/mobile/Documents/" + configFileName)

        // /var/mobile/Library/Caches
        paths.append("/var/mobile/Library/Caches/" + configFileName)

        // App 自身的 Documents
        if let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first {
            paths.append(docs.appendingPathComponent(configFileName).path)
        }

        // App Group 共享容器（如果已配置）
        if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.virtuallocation.shared"
        ) {
            paths.append(groupURL.appendingPathComponent(configFileName).path)
        }

        return paths
    }

    // MARK: - Write

    func write(config: [String: Any]) {
        let plistDict = configToPlist(config)

        for path in targetPaths {
            do {
                let dir = NSString(string: path).deletingLastPathComponent
                try FileManager.default.createDirectory(
                    atPath: dir,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                let plistData = try PropertyListSerialization.data(
                    fromPropertyList: plistDict,
                    format: .xml,
                    options: 0
                )
                try plistData.write(to: URL(fileURLWithPath: path), options: .atomic)
                NSLog("[VirtualLocation] ✅ 配置已写入: " + path)
            } catch {
                NSLog("[VirtualLocation] ⚠️ 写入失败: " + path + " error: " + error.localizedDescription)
            }
        }
    }

    // MARK: - Read

    func read() -> [String: Any]? {
        for path in targetPaths {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                let plist = try PropertyListSerialization.propertyList(
                    from: data, options: [], format: nil
                )
                if let dict = plist as? [String: Any] {
                    return dict
                }
            } catch {
                continue
            }
        }
        return nil
    }

    // MARK: - Helpers

    private func configToPlist(_ config: [String: Any]) -> [String: Any] {
        var plist: [String: Any] = [:]

        plist["enabled"] = config["enabled"] as? Bool ?? false
        plist["latitude"] = config["latitude"] as? Double ?? 31.2304
        plist["longitude"] = config["longitude"] as? Double ?? 121.4737
        plist["altitude"] = config["altitude"] as? Double ?? 10.0
        plist["horizontalAccuracy"] = config["horizontalAccuracy"] as? Double ?? 5.0
        plist["verticalAccuracy"] = config["verticalAccuracy"] as? Double ?? 5.0
        plist["speed"] = config["speed"] as? Double ?? 0.0
        plist["course"] = config["course"] as? Double ?? 0.0

        if let ts = config["timestamp"] as? TimeInterval, ts > 0 {
            plist["timestamp"] = Date(timeIntervalSince1970: ts)
        } else {
            plist["timestamp"] = Date()
        }

        return plist
    }
}
