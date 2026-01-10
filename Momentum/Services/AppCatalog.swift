//
//  AppCatalog.swift
//  Momentum
//
//  Created by Codex on 24/11/25.
//

import AppKit
import Foundation

@MainActor
final class AppCatalog: ObservableObject {
    private struct AppDescriptor: Hashable, Sendable {
        let bundleIdentifier: String
        let name: String
        let url: URL
    }

    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var isLoading = false

    private let searchPaths: [URL]

    init(searchPaths: [URL]? = nil, initialApps: [InstalledApp]? = nil) {
        self.searchPaths = searchPaths ?? AppCatalog.defaultSearchPaths
        if let initialApps {
            apps = initialApps
        } else {
            refresh()
        }
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        Task.detached { [weak self, searchPaths] in
            guard let self else { return }
            let discovered = Self.scanApplications(at: searchPaths)
            let sorted = discovered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            await MainActor.run {
                self.apps = Self.makeInstalledApps(from: sorted)
                self.isLoading = false
            }
        }
    }

    func app(for identifier: String) -> InstalledApp? {
        apps.first { $0.bundleIdentifier == identifier }
    }
}

private extension AppCatalog {
    nonisolated static var defaultSearchPaths: [URL] {
        var paths: [URL] = []
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        [
            "/Applications",
            "\(home.path)/Applications",
            "\(home.path)/Library/Application Support/Setapp/Applications",
        ].forEach { path in
            let url = URL(fileURLWithPath: path, isDirectory: true)
            if fm.fileExists(atPath: url.path) {
                paths.append(url)
            }
        }
        return paths
    }

    nonisolated private static func scanApplications(at paths: [URL]) -> [AppDescriptor] {
        var results: [String: AppDescriptor] = [:]
        let keys: [URLResourceKey] = [.isDirectoryKey]
        let fm = FileManager.default
        for root in paths {
            guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
                continue
            }
            for case let url as URL in enumerator {
                guard url.pathExtension == "app" else { continue }
                guard let bundle = Bundle(url: url),
                      let identifier = bundle.bundleIdentifier,
                      let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
                      bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ??
                      url.deletingPathExtension().lastPathComponent as String?
                else {
                    continue
                }
                if results[identifier] != nil {
                    continue
                }
                let app = AppDescriptor(bundleIdentifier: identifier, name: name, url: url)
                results[identifier] = app
            }
        }
        ensureSystemApps(into: &results)
        return Array(results.values)
    }

    nonisolated private static func ensureSystemApps(into results: inout [String: AppDescriptor]) {
        let fm = FileManager.default
        let entries: [(String, String, String)] = [
            ("com.apple.Safari", "Safari", "/Applications/Safari.app"),
            ("com.apple.mail", "Mail", "/System/Applications/Mail.app"),
            ("com.apple.iCal", "Calendario", "/System/Applications/Calendar.app"),
            ("com.apple.Notes", "Notas", "/System/Applications/Notes.app"),
            ("com.apple.Terminal", "Terminal", "/System/Applications/Utilities/Terminal.app"),
        ]
        for entry in entries {
            guard results[entry.0] == nil else { continue }
            let url = URL(fileURLWithPath: entry.2)
            guard fm.fileExists(atPath: url.path) else { continue }
            results[entry.0] = AppDescriptor(bundleIdentifier: entry.0, name: entry.1, url: url)
        }
    }

    @MainActor
    private static func makeInstalledApps(from descriptors: [AppDescriptor]) -> [InstalledApp] {
        descriptors.map { descriptor in
            let icon = NSWorkspace.shared.icon(forFile: descriptor.url.path)
            icon.size = NSSize(width: 32, height: 32)
            return InstalledApp(
                bundleIdentifier: descriptor.bundleIdentifier,
                name: descriptor.name,
                url: descriptor.url,
                icon: icon
            )
        }
    }
}
