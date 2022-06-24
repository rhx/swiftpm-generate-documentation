import Foundation

struct Package: Hashable, Codable {

    var targets: [Target]

    init(dumpPackageUsing swiftBin: String = "/usr/bin/swift") throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: swiftBin, isDirectory: false)
        process.arguments = ["package", "dump-package"]
        let pipe = Pipe()
        process.standardOutput = pipe
        print(([process.executableURL?.path  ?? ""] + (process.arguments ?? [])).joined(separator: " "))
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            fatalError("Unable to dump package")
        }
        guard let data = try pipe.fileHandleForReading.readToEnd() else {
            fatalError("Failed to read package dump")
        }
        let decoder = JSONDecoder()
        var package = try decoder.decode(Package.self, from: data)
        let fm = FileManager.default
        let srcDir = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true).appendingPathComponent("Sources", isDirectory: true)
        package.targets = package.targets.compactMap {
            if $0.type == .unsupported {
                return nil
            }
            if $0.type != .regular {
                return $0
            }
            let targetDir = srcDir.appendingPathComponent($0.name, isDirectory: true)
            guard let enumerator = fm.enumerator(at: targetDir, includingPropertiesForKeys: nil) else {
                return nil
            }
            let files: [URL] = enumerator.allObjects.compactMap {
                guard let url = $0 as? URL, !url.hasDirectoryPath else {
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
        self = package
    }

    func generateDocumentation(swiftBin: String = "/usr/bin/swift", hostingBasePath: String?, outputPath: String = "./docs") throws {
        for target in targets where target.type == .swift || target.type == .C {
            try target.generateDocumentation(swiftBin: swiftBin, hostingBasePath: hostingBasePath, outputPath: outputPath)
        }
    }

}

struct Target: Hashable, Codable {

    enum TargetType: String, Hashable, Codable {

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
            try container.encode(rawValue, forKey: .type)
        }

    }

    var name: String

    var type: TargetType

    func generateDocumentation(swiftBin: String = "/usr/bin/swift", hostingBasePath: String?, outputPath: String = "./docs") throws {
        switch type {
        case .swift:
            try generateSwiftDocumentation(swiftBin: swiftBin, hostingBasePath: hostingBasePath, outputPath: outputPath)
        default:
            return
        }
    }
    

    private func generateSwiftDocumentation(swiftBin: String, hostingBasePath: String?, outputPath: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: swiftBin, isDirectory: false)
        process.arguments = ["package", "--allow-writing-to-directory", outputPath, "generate-documentation", "--target", self.name, "--disable-indexing", "--transform-for-static-hosting"] + (hostingBasePath != nil ? ["--hosting-base-path", hostingBasePath!] : []) + ["--output-path", outputPath]
        print(([process.executableURL?.path  ?? ""] + (process.arguments ?? [])).joined(separator: " "))
        do {
            try process.run()
        } catch let e {
            fatalError(e.localizedDescription)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            fatalError("Unable to generate documentation for target \(self.name)")
        }
    }

}

let swiftBin = "swift"
print(swiftBin)
let outputPath = ProcessInfo.processInfo.environment["INPUT_OUTPUT_PATH"] ?? "./docs"
let hostingBasePath = ProcessInfo.processInfo.environment["INPUT_HOSTING_BASE_PATH"]

do {
    let package = try Package(dumpPackageUsing: swiftBin)
    try package.generateDocumentation(swiftBin: swiftBin, hostingBasePath: hostingBasePath, outputPath: outputPath)
} catch let e {
    fatalError(e.localizedDescription)
}
