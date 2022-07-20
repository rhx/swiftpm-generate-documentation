import Foundation

struct Package: Hashable, Decodable {

    var targets: [Target]

    init(targets: [Target]) {
        self.targets = targets
    }

    init(dumpPackageUsing swiftBin: String = "/usr/bin/swift", inDirectory workingDirectory: URL) throws {
        let fm = FileManager.default
        let currentDirectoryPath = fm.currentDirectoryPath
        fm.changeCurrentDirectoryPath(workingDirectory.path)
        defer { fm.changeCurrentDirectoryPath(currentDirectoryPath) }
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

    func generateDocumentation(swiftBin: String = "/usr/bin/swift", inDirectory workingDirectory: URL, hostingBasePath: String?, outputPath: URL) throws {
        let fm = FileManager.default
        let currentDirectoryPath = fm.currentDirectoryPath
        fm.changeCurrentDirectoryPath(workingDirectory.path)
        defer { fm.changeCurrentDirectoryPath(currentDirectoryPath) }
        for target in targets where target.type == .swift || target.type == .C {
            try target.generateDocumentation(swiftBin: swiftBin, hostingBasePath: hostingBasePath, outputPath: outputPath)
        }
    }

}

struct Target: Hashable, Decodable {

    enum TargetType: String, Hashable {

        case swift
        case C
        case regular
        case unsupported

    }

    enum CodingKeys: CodingKey {
            
            case name
            case type
    
    }

    var name: String

    var type: TargetType

    init(name: String, type: TargetType) {
        self.name = name
        self.type = type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        let typeRawValue = try container.decode(String.self, forKey: .type)
        let type = TargetType(rawValue: typeRawValue) ?? .unsupported
        self.init(name: name, type: type)
    }

    func generateDocumentation(swiftBin: String = "/usr/bin/swift", hostingBasePath: String?, outputPath: URL) throws {
        switch type {
        case .swift:
            try generateSwiftDocumentation(swiftBin: swiftBin, hostingBasePath: hostingBasePath, outputPath: outputPath)
        default:
            return
        }
    }
    

    private func generateSwiftDocumentation(swiftBin: String, hostingBasePath: String?, outputPath: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: swiftBin, isDirectory: false)
        process.arguments = [
            "package",
            "--allow-writing-to-directory", outputPath.path,
            "generate-documentation",
            "--target", self.name,
            "--disable-indexing",
            "--transform-for-static-hosting"
        ] + (hostingBasePath != nil ? ["--hosting-base-path", hostingBasePath!] : []) + ["--output-path", outputPath.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            fatalError("Unable to generate documentation for target \(self.name)")
        }
    }

}

func parseArg(_ argument: String) -> String? {
    let raw = CommandLine.arguments.firstIndex(of: argument).flatMap { CommandLine.arguments.count <= $0 + 1 ? nil : CommandLine.arguments[$0 + 1].trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
    return raw.prefix(2) == "--" || raw.isEmpty ? nil : raw
}

let swiftBin = "/Users/runner/hostedtoolcache/swift-macOS/5.6.1/x64/usr/bin/swift"
print(swiftBin)
let outputPath = parseArg("--output-path").map { URL(fileURLWithPath: $0, isDirectory: true) } ?? URL(fileURLWithPath: "./docs", isDirectory: true)
let hostingBasePath = parseArg("--hosting-base-path")
let workingDirectory = URL(fileURLWithPath: parseArg("--working-directory") ?? FileManager.default.currentDirectoryPath, isDirectory: true)

do {
    let package = try Package(dumpPackageUsing: swiftBin, inDirectory: workingDirectory)
    guard package.targets.contains(where: { $0.type != .unsupported }) else {
        print("warning: No targets to document found.")
        exit(EXIT_SUCCESS)
    }
    try package.generateDocumentation(swiftBin: swiftBin, inDirectory: workingDirectory, hostingBasePath: hostingBasePath, outputPath: outputPath)
    if package.targets.filter({ $0.type != .unsupported }).count == 1, let first = package.targets.first(where: { $0.type != .unsupported }) {
        let indexURL = outputPath.appendingPathComponent("index.html", isDirectory: false)
        let content = """
            <!DOCTYPE html>
            <html lang="en">
            <head>
                <title>\(first.name)</title>
                <meta http-equiv = "refresh" content = "0; url = /\(hostingBasePath.map { $0 + "/" } ?? "")documentation/\(first.name.lowercased())" />
            </head>
            <body>
                <p>Redirecting</p>
            </body>
            """
        try content.write(to: indexURL, atomically: true, encoding: .utf8)
    }
} catch let e {
    fatalError(e.localizedDescription)
}
