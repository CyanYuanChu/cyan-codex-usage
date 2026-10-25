import SwiftUI
import AppKit

@MainActor final class FeatureController: ObservableObject {
    let codex = CodexStore()
    var content: AnyView { AnyView(CodexDashboardView(store: codex, p: GrovePalette())) }
    func start() { codex.start() }
    func stop() { codex.stop() }
    func refresh() { Task { await codex.refreshQuota(); await codex.scan() } }
    func perform(_ action: String) async {}
    var summary: [String:String] { ["剩余额度": SystemReading.percent(codex.quota?.preferredWindow?.remaining), "今日 Token": String(codex.usage.total(range: "today").tokens.total), "状态": codex.quotaError ?? (codex.scanning ? "正在扫描" : "本机统计")] }
}

extension FeatureController { var menuImage: NSImage? { nil } }

extension FeatureController { var previewContent: AnyView { content } }
