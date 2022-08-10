import Foundation

struct Package: Hashable, Decodable {

    var name: String

    var targets: [Target]

    init(name: String, targets: [Target]) {
        self.name = name
        self.targets = targets
    }

    init(dumpPackageUsing swiftBin: String = "/usr/bin/swift") throws {
        let fm = FileManager.default
        let process = Process()
        process.executableURL = URL(fileURLWithPath: swiftBin, isDirectory: false)
        process.arguments = ["package", "dump-package"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.currentDirectoryURL = URL(fileURLWithPath: fm.currentDirectoryPath)
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

    /*
    private func dumpSymbolGraph(using swiftBin: String, minimumAccessLevel: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: swiftBin, isDirectory: false)
        process.arguments = ["package", "dump-symbol-graph", "--minimum-access-level", minimumAccessLevel]
    }*/

    func generateDocumentation(swiftBin: String = "/usr/bin/swift", hostingBasePath: String?, outputPath: URL, minimumAccessLevel: String) throws {
        for target in targets where target.type == .swift || target.type == .C {
            try target.generateDocumentation(swiftBin: swiftBin, hostingBasePath: hostingBasePath, outputPath: outputPath, minimumAccessLevel: minimumAccessLevel)
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

    func generateDocumentation(swiftBin: String = "/usr/bin/swift", hostingBasePath: String?, outputPath: URL, minimumAccessLevel: String) throws {
        switch type {
        case .swift:
            try generateSwiftDocumentation(swiftBin: swiftBin, hostingBasePath: hostingBasePath, outputPath: outputPath, minimumAccessLevel: minimumAccessLevel)
        default:
            return
        }
    }
    

    private func generateSwiftDocumentation(swiftBin: String, hostingBasePath: String?, outputPath: URL, minimumAccessLevel: String) throws {
        let fm = FileManager.default
        let process = Process()
        let hostingBasePath = hostingBasePath.map { "/" + $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/" + self.name } ?? self.name
        process.executableURL = URL(fileURLWithPath: swiftBin, isDirectory: false)
        process.arguments = [
            "package",
            "--allow-writing-to-directory", outputPath.path,
            "-Xswiftc",
            "-symbol-graph-minimum-access-level",
            "-Xswiftc",
            minimumAccessLevel,
            "generate-documentation",
            "--target", self.name,
            "--disable-indexing",
            "--transform-for-static-hosting",
            "--hosting-base-path", hostingBasePath,
            "--output-path", outputPath.appendingPathComponent(self.name, isDirectory: true).path
        ]
        process.currentDirectoryURL = URL(fileURLWithPath: fm.currentDirectoryPath)
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

func parsePath(_ argument: String, relativeTo basePath: URL) -> URL? {
    parseArg(argument).map { $0.hasPrefix("/") ? URL(fileURLWithPath: $0, isDirectory: true) :  basePath.appendingPathComponent($0, isDirectory: true) }
}

#if os(macOS)
let swiftBin = "/Users/runner/hostedtoolcache/swift-macOS/5.6.1/x64/usr/bin/swift"
#else
let swiftBin = "/opt/hostedtoolcache/swift-Ubuntu/5.6.1/x64/usr/bin/swift"
#endif
print(swiftBin)
let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let minimumAccessLevel = parseArg("--minimum-access-level") ?? "public"
let hostingBasePath = parseArg("--hosting-base-path").flatMap { $0 == "/" ? nil : $0 }
let workingDirectory = parsePath("--working-directory", relativeTo: currentDirectory) ?? currentDirectory
let outputPath = parsePath("--output-path", relativeTo: workingDirectory) ?? workingDirectory.appendingPathComponent("docs", isDirectory: true)

let fm = FileManager.default
fm.changeCurrentDirectoryPath(workingDirectory.path)

let package: Package
do {
    package = try Package(dumpPackageUsing: swiftBin)
    guard package.targets.contains(where: { $0.type != .unsupported }) else {
        print("warning: No targets to document found.")
        exit(EXIT_SUCCESS)
    }
} catch let e {
    fatalError("Error parsing Package.swift: " + e.localizedDescription)
}
do {
    try FileManager.default.createDirectory(at: outputPath, withIntermediateDirectories: true)
    try package.generateDocumentation(swiftBin: swiftBin, hostingBasePath: hostingBasePath, outputPath: outputPath, minimumAccessLevel: minimumAccessLevel)
    let indexURL = outputPath.appendingPathComponent("index.html", isDirectory: false)
    if package.targets.filter({ $0.type != .unsupported }).count == 1, let first = package.targets.first(where: { $0.type != .unsupported }) {
        let documentationDirectory = "/" + (hostingBasePath.map { $0 + "/" } ?? "") + first.name + "/documentation"
        let content = """
            <!DOCTYPE html>
            <html lang="en">
            <head>
                <title>\(first.name)</title>
                <meta http-equiv = "refresh" content = "0; url = \(documentationDirectory)/\(first.name.lowercased())" />
            </head>
            <body>
                <p>Redirecting</p>
            </body>
            </html>
            """
        try content.write(to: indexURL, atomically: true, encoding: .utf8)
    } else {
        let targets = package.targets.filter { $0.type != .unsupported }.map { $0.name }.sorted()
        let head = """
            <!DOCTYPE html>
            <html lang="en">
            <head>
                <title>\(package.name) Documentation</title>
            </head>
            <body>
            <h1>Targets</h1>
            """
        let targetContent = targets.map {
            let documentationDirectory = "/" + (hostingBasePath.map { $0 + "/" } ?? "") + $0 + "/documentation"
            return """
            <h2><a href="\(documentationDirectory)/\($0.lowercased())">\($0)</a></h2>
            """
        }.joined(separator: "\n")
        let tail = "</body>\n</html>"
        let content = head + "\n" + targetContent + "\n" + tail
        try content.write(to: indexURL, atomically: true, encoding: .utf8)
    }
} catch let e {
    fatalError("Error Generating Documentation: " + e.localizedDescription)
}
