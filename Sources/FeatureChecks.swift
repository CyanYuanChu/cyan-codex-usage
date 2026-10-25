import Foundation
import AppKit
@MainActor enum FeatureChecks {
    static func run() async {
        var failed = 0
        func check(_ condition: Bool, _ name: String) { print((condition ? "PASS " : "FAIL ") + name); if !condition { failed += 1 } }
        check(ModuleMetadata.value["protocolVersion"] as? Int == 1, "module protocol metadata")
        check(!ModuleMetadata.id.contains("/"), "stable module identity")
        check(FileManager.default.fileExists(atPath: Bundle.main.resourcePath! + "/module.json"), "standalone manifest bundled")
        let q = try? CodexQuota.parse(["rateLimits": ["primary": ["usedPercent": 12,"windowDurationMins": 10080]]])
        check(q?.preferredWindow?.remaining == 88, "remaining quota conversion")
        let a = TokenCounts(input: 100, cached: 70, output: 20, reasoning: 10)
        check(a.total == 120, "cached and reasoning not double counted")
        check(CodexLocalData.storage.lastPathComponent == "CyanCodexUsage", "independent data directory")
        print("MODULE_TESTS \(failed == 0 ? "OK" : "FAILED")")
        if failed > 0 { exit(1) }
    }
}
