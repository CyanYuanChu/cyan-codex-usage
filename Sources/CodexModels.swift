import Foundation

struct QuotaWindow: Codable, Identifiable {
    var id: String; var bucket: String; var minutes: Int?; var used: Double; var resets: Date?
    var remaining: Double { max(0,min(100,100-used)) }
    var title: String {
        guard let minutes else { return "\(bucket) · 时长未知" }
        let period = minutes == 10080 ? "每周额度" : minutes == 300 ? "5 小时额度" : minutes >= 1440 ? "\(minutes/1440) 天额度" : "\(minutes) 分钟额度"
        return bucket == "codex" ? period : "\(bucket) · \(period)"
    }
}
struct CodexQuota: Codable {
    var windows: [QuotaWindow]; var plan: String?; var resetCredits: Int?; var date: Date
    var preferredWindow: QuotaWindow? { windows.first { $0.bucket == "codex" && $0.minutes == 10080 } ?? windows.first { $0.bucket == "codex" } ?? windows.first }
    static func parse(_ result: [String:Any]) throws -> Self {
        var buckets = result["rateLimitsByLimitId"] as? [String:[String:Any]] ?? [:]
        if buckets.isEmpty, let legacy = result["rateLimits"] as? [String:Any] { buckets[legacy["limitId"] as? String ?? "codex"] = legacy }
        var windows: [QuotaWindow] = []
        for (key,bucket) in buckets.sorted(by: {$0.key < $1.key}) {
            for name in ["primary","secondary"] {
                guard let w = bucket[name] as? [String:Any], let used = (w["usedPercent"] as? NSNumber)?.doubleValue, used.isFinite else { continue }
                windows.append(QuotaWindow(id: key+name, bucket: key, minutes: w["windowDurationMins"] as? Int, used: max(0,min(100,used)), resets: (w["resetsAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }))
            }
        }
        guard !windows.isEmpty else { throw GroveError.message("尚未返回额度窗口；请确认 Codex 已登录。") }
        return Self(windows: windows, plan: buckets["codex"]?["planType"] as? String, resetCredits: (result["rateLimitResetCredits"] as? [String:Any])?["availableCount"] as? Int, date: .now)
    }
}
struct TokenCounts: Codable, Equatable {
    var input = 0; var cached = 0; var output = 0; var reasoning = 0
    var total: Int { input+output }
    var valid: Bool { input >= 0 && output >= 0 && input <= 9_007_199_254_740_991 && output <= 9_007_199_254_740_991 && input >= cached && output >= reasoning && cached >= 0 && reasoning >= 0 && total <= 9_007_199_254_740_991 }
    init(input: Int = 0, cached: Int = 0, output: Int = 0, reasoning: Int = 0) { self.input=input; self.cached=cached; self.output=output; self.reasoning=reasoning }
    init(_ object: [String:Any]) { input=object["input_tokens"] as? Int ?? 0; cached=object["cached_input_tokens"] as? Int ?? 0; output=object["output_tokens"] as? Int ?? 0; reasoning=object["reasoning_output_tokens"] as? Int ?? 0 }
    func delta(_ previous: Self) -> Self? {
        let d = Self(input: input-previous.input, cached: cached-previous.cached, output: output-previous.output, reasoning: reasoning-previous.reasoning)
        return d.input >= 0 && d.output >= 0 && d.valid ? d : nil
    }
    static func + (a: Self,b: Self) -> Self { Self(input:a.input+b.input,cached:a.cached+b.cached,output:a.output+b.output,reasoning:a.reasoning+b.reasoning) }
}
struct UsageEvent: Codable {
    var stamp: String; var day: String; var model: String; var total: TokenCounts; var delta: TokenCounts; var cost: Double?
}
struct SessionUsage: Codable {
    var id: String; var parent: String?; var fork: String?; var project: String; var title: String; var modified: Date; var size: Int
    var events: [UsageEvent]; var partial: Bool
}
struct UsageTotal {
    var tokens = TokenCounts(); var cost: Double? = 0; var events = 0
    mutating func add(_ event: UsageEvent) {
        tokens = tokens + event.delta; events += 1
        if let a = cost, let b = event.cost { cost = a+b } else { cost = nil }
    }
}
struct UsageRow: Identifiable {
    var id: String; var title: String; var detail: String; var total: UsageTotal
}
struct CodexUsage {
    var sessions: [SessionUsage] = []; var date = Date.distantPast; var partial = false; var warnings = 0
    var events: [(String,UsageEvent)] = []
    func rows(range: String, kind: String, selectedDay: String? = nil) -> [UsageRow] {
        let accepted = filtered(range: range, selectedDay: selectedDay)
        var groups: [String:UsageRow] = [:]
        let index = Dictionary(sessions.map { ($0.id,$0) }, uniquingKeysWith: { a,_ in a })
        for (id,event) in accepted {
            let key = kind == "model" ? event.model : kind == "project" ? (index[id]?.project ?? "未归类") : id
            let title = kind == "task" ? (index[id]?.title ?? String(id.suffix(8))) : key
            var row = groups[key] ?? UsageRow(id:key,title:title,detail: kind == "task" ? (index[id]?.project ?? "") : "",total:UsageTotal())
            row.total.add(event);groups[key] = row
        }
        return groups.values.sorted { $0.total.tokens.total > $1.total.tokens.total }
    }
    func filtered(range: String, selectedDay: String? = nil) -> [(String,UsageEvent)] {
        let today = Self.day(Date()), start: String
        switch range {
        case "today": start=today
        case "week": start=Self.day(Calendar.current.date(byAdding:.day,value:-6,to:Date())!)
        case "month": start=Self.day(Calendar.current.date(byAdding:.day,value:-29,to:Date())!)
        default: start="0000"
        }
        return events.filter { pair in selectedDay.map { $0 == pair.1.day } ?? (pair.1.day >= start && pair.1.day <= today) }
    }
    func total(range: String, selectedDay: String? = nil) -> UsageTotal { var t=UsageTotal();for (_,e) in filtered(range:range,selectedDay:selectedDay) { t.add(e) };return t }
    var daily: [String:UsageTotal] { var d:[String:UsageTotal]=[:];for (_,e) in events { var t=d[e.day] ?? UsageTotal();t.add(e);d[e.day]=t };return d }
    static func day(_ date: Date) -> String { let f=DateFormatter();f.locale=Locale(identifier:"en_US_POSIX");f.dateFormat="yyyy-MM-dd";return f.string(from:date) }
}

enum CodexPricing {
    // Ported from Cockpit's dated offline catalog; API-equivalent estimates, not subscription billing.
    static let rates: [String:(Double,Double,Double)] = ["gpt-6.1-sol":(2,0.1,10),"gpt-6-astra":(10,1,50),"gpt-6-sol":(2,0.2,10),"gpt-6-luna":(0.1,0.01,0.5),"gpt-5.6-sol":(4,0.4,20),"gpt-5.6-terra":(2,0.2,12),"gpt-5.6-luna":(0.2,0.02,1.2)]
    static func estimate(model: String, delta: TokenCounts, context: TokenCounts?) -> Double? {
        let key = model.hasPrefix("openai/") ? String(model.dropFirst(7)) : model
        guard let rate=rates[key] else { return delta.total == 0 ? 0 : nil }
        var input=rate.0, cache=rate.1, output=rate.2
        guard let context,context.valid,context == delta else { return delta.total == 0 ? 0 : nil }
        if context.input > 272_000 { input *= 2;cache *= 2;output *= 1.5 }
        return (Double(delta.input-delta.cached)*input + Double(delta.cached)*cache + Double(delta.output)*output)/1_000_000
    }
}

struct QuotaObservation:Codable,Identifiable {
    var date:Date;var remaining:Double;var resets:Date?
    var id:Date{date}
}
