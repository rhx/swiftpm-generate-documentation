#! /usr/bin/env swift

import Foundation

struct Package: Hashable, Codable {

    var target: [Target]

}

struct Target: Hashable, Codable {

    enum Type: String, Hashable, Codable {

        enum CodingKeys: String, CodingKey {
            case type
        }

        case swift
        case C
        case regular
        case unsupported

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            switch type {
            case "swift", "C", "regular":
                self = .init(rawValue: type)!
            default:
                self = .unsupported
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            container.encode(rawValue, forKey: .type)
        }

    }

    var name: String

    var type: Type
}

func fetchTarget() {

}

let targets: [Target] = try {
    do {
        let process = try Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift", isDirectory: false)
        process.arguments = ["package", "dump-package"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            fatalError("Unable to dump package")
        }
        guard let data = try pipe.fileHandleForReading.readtoEnd() else {
            fatalError("Failed to read package dump")
        }
        let decoder = JSONDecoder()
        let package = try decoder.decode(Package.self, from: data)
        let fm = FileManager.default
        let srcDir = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true).appendingPathComponent("Sources", isDirectory: true)
        return package.targets.compactMap {
            if $0.type == .unknown {
                return nil
            }
            if $0.type != .regular {
                return $0
            }
            let targetDir = srcDir.appendingPathComponent($0.name, isDirectory: true)
            guard let enumerator = fm.enumerator(at: targetDir, includingPropertiesForKeys: nil) else {
                return nil
            }
            let files = enumerator.allObjects.compactMap {
                guard let url = $0 as? URL, !url.isDirectory else {
                    return nil
                }
                return url
            }
            if files.contains(where: { $0.pathExtension == "swift" }) {
                return Target(name: $0.name, type: .swift)
            } else if files.contains(where: { $0.pathExtension == "c" || $0.pathExtension == "h" || $0.pathExtension == "hpp" || $0.pathExtension == "cc" || $0.pathExtension == "cpp" }) {
                return Target(name: $0.name, type: .C)
            } else {
                return nil
            }
        }
    } catch let e {
        fatalError(e.localizedDescription)
    }
}()

let outputPath = ProcessInfo.environment["INPUT_OUTPUT_PATH"]
let hostingBasePath = ProcessInfo.environment["INPUT_HOSTING_BASE_PATH"]

func generateDocCDocumentation(for target: Target, hostingBasePath: String?, outputPath: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/swift", isDirectory: false)
    process.arguments = ["package", "--allow-writing-to-directory", outputPath, "generate-documentation", "--target", target.name, "--disable-indexing", "--transform-for-static-hosting"] + (hostingBasePath != nil ? ["--hosting-base-path", hostingBasePath!] : []) + ["--output-path", outputPath]
    process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        fatalError("Unable to generate documentation for target \(target.name)")
    }
}

for target in targets where target.type == .swift {
    generateDocCDocumentation(for: target, hostingBasePath: hostingBasePath, outputPath: outputPath ?? "./docs")
}
