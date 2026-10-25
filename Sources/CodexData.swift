import Foundation
import Darwin

// Only metadata and token events are retained. No credentials or message content are copied.
enum CodexLocalData {
    static var root: URL {
        if let path=ProcessInfo.processInfo.environment["CODEX_HOME"],!path.isEmpty { return URL(fileURLWithPath:path) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }
    static var storage: URL { FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("CyanCodexUsage") }
    static func save<T:Encodable>(_ value:T, _ name:String) throws {
        try FileManager.default.createDirectory(at:storage,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let url=storage.appendingPathComponent(name)
        try JSONEncoder().encode(value).write(to:url,options:[.atomic,.completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
    }
    static func load<T:Decodable>(_ type:T.Type,_ name:String) -> T? { guard let d=try? Data(contentsOf:storage.appendingPathComponent(name)) else{return nil};return try? JSONDecoder().decode(type,from:d) }
    static func lines(_ url:URL, limit:Int = 512*1024*1024, consume:(Data)->Void) throws -> Bool {
        let handle=try FileHandle(forReadingFrom:url);defer{try? handle.close()}
        var pending=Data(), bytes=0, discarding=false, partial=false
        while let chunk=try handle.read(upToCount:262144),!chunk.isEmpty {
            bytes += chunk.count
            if bytes>limit {partial=true;break}
            pending.append(chunk)
            while let end=pending.firstIndex(of:10) {
                let line=pending.prefix(upTo:end)
                if !discarding && line.count<=2*1024*1024 { consume(Data(line)) } else {partial=true}
                pending.removeSubrange(...end);discarding=false
            }
            if pending.count>2*1024*1024 { pending.removeAll(keepingCapacity:true);discarding=true;partial=true }
        }
        return partial || !pending.isEmpty || discarding
    }
    static func parseSession(_ url:URL,modified:Date,size:Int) throws -> SessionUsage {
        var session=SessionUsage(id:url.deletingPathExtension().lastPathComponent,parent:nil,fork:nil,project:"未归类",title:"",modified:modified,size:size,events:[],partial:false)
        var model="unknown", previous=TokenCounts(),first=true
        let iso=ISO8601DateFormatter();iso.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
        let fallback=ISO8601DateFormatter()
        var malformed=false
        let partial=try lines(url) { line in
            // Avoid decoding unrelated messages, prompts and tool payloads.
            guard line.range(of:Data("\"session_meta\"".utf8)) != nil || line.range(of:Data("\"turn_context\"".utf8)) != nil || line.range(of:Data("\"token_count\"".utf8)) != nil else {return}
            guard let object=(try? JSONSerialization.jsonObject(with:line)) as? [String:Any],let kind=object["type"] as? String,let payload=object["payload"] as? [String:Any] else {malformed=true;return}
            if kind=="session_meta" {
                session.id=payload["id"] as? String ?? session.id
                session.parent=payload["parent_thread_id"] as? String;session.fork=payload["forked_from_id"] as? String
                if let cwd=payload["cwd"] as? String {session.project=URL(fileURLWithPath:cwd).lastPathComponent}
            } else if kind=="turn_context" {
                model=payload["model"] as? String ?? "unknown"
            } else if kind=="event_msg",payload["type"] as? String == "token_count",let info=payload["info"] as? [String:Any] {
                guard let raw=info["total_token_usage"] as? [String:Any] else{malformed=true;return}
                let total=TokenCounts(raw);guard total.valid else{malformed=true;return}
                let last=(info["last_token_usage"] as? [String:Any]).map(TokenCounts.init)
                let delta:TokenCounts?
                if first && session.fork != nil { delta=last.flatMap { $0.valid && total.delta($0) != nil ? $0 : nil }; malformed=true }
                else { delta=total.delta(previous) }
                previous=total;first=false
                guard let delta else{malformed=true;return}
                guard delta.total>0 else{return}
                guard let stamp=object["timestamp"] as? String,let date=iso.date(from:stamp) ?? fallback.date(from:stamp),date.timeIntervalSinceNow<300 else{malformed=true;return}
                let price=CodexPricing.estimate(model:model,delta:delta,context:last)
                session.events.append(UsageEvent(stamp:stamp,day:CodexUsage.day(date),model:model,total:total,delta:delta,cost:price))
            }
        }
        session.title="\(session.project) · \(session.id.suffix(6))"
        session.partial=partial || malformed
        return session
    }
    static func scan(at root:URL = root, useCache:Bool = true) throws -> CodexUsage {
        let fm=FileManager.default
        guard fm.fileExists(atPath:root.appendingPathComponent("sessions").path) else{throw GroveError.message("未找到本机 Codex 会话目录。请先运行 Codex。")}
        var titles:[String:String]=[:]
        let index=root.appendingPathComponent("session_index.jsonl")
        if fm.fileExists(atPath:index.path) {
            _ = try? lines(index,limit:32*1024*1024) { data in
                if let v=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],let id=v["id"] as? String,let title=(v["thread_name"] ?? v["title"]) as? String { titles[id]=String(title.filter{!$0.isNewline && !$0.isASCIIControl}.prefix(180)) }
            }
        }
        let cache=useCache ? load([String:SessionUsage].self,"session-index-v2.json") ?? [:] : [:]
        var updated:[String:SessionUsage]=[:],sessions:[SessionUsage]=[], partial=false
        var files:[URL]=[]
        for folder in ["sessions","archived_sessions"] {
            guard let enumerator=fm.enumerator(at:root.appendingPathComponent(folder),includingPropertiesForKeys:[.isRegularFileKey,.isSymbolicLinkKey,.contentModificationDateKey,.fileSizeKey],options:[.skipsHiddenFiles]) else{continue}
            while let url=enumerator.nextObject() as? URL {
                let v=try? url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey])
                if v?.isSymbolicLink==true {enumerator.skipDescendants();continue}
                if url.pathExtension=="jsonl",v?.isRegularFile==true {files.append(url)}
            }
        }
        if files.count>4000 {partial=true;files=Array(files.sorted{ $0.path > $1.path }.prefix(4000))}
        for url in files {
            do {
                let values=try url.resourceValues(forKeys:[.contentModificationDateKey,.fileSizeKey])
                let modified=values.contentModificationDate ?? .distantPast,size=values.fileSize ?? 0
                var session:SessionUsage
                if let old=cache[url.path],old.modified==modified,old.size==size {session=old}
                else {session=try parseSession(url,modified:modified,size:size)}
                if let title=titles[session.id],!title.isEmpty {session.title=title}
                if session.partial, let old=cache[url.path], session.events.count < old.events.count, size>=old.size {
                    session=old;session.partial=true
                }
                updated[url.path]=session;sessions.append(session);partial = partial || session.partial
            } catch {
                partial=true
                if var old=cache[url.path] {old.partial=true;updated[url.path]=old;sessions.append(old)}
            }
        }
        if useCache {try save(updated,"session-index-v2.json")}
        let unique=Dictionary(sessions.map{($0.id,$0)},uniquingKeysWith:{a,b in a.events.count>=b.events.count ? a:b})
        func lineage(_ id:String) -> String {
            var cursor=id,seen=Set<String>()
            while seen.insert(cursor).inserted,let next=unique[cursor]?.fork {cursor=next}
            return cursor
        }
        var seen=Set<String>(),events:[(String,UsageEvent)]=[]
        for session in unique.values.sorted(by:{$0.fork == nil && $1.fork != nil}) {
            let root=lineage(session.id)
            for event in session.events {
                let key="\(root)|\(event.stamp)|\(event.total.input)|\(event.total.cached)|\(event.total.output)|\(event.total.reasoning)"
                if seen.insert(key).inserted {events.append((session.id,event))}
            }
        }
        return CodexUsage(sessions:Array(unique.values),date:.now,partial:partial,warnings:partial ? 1:0,events:events)
    }
}
private extension Character { var isASCIIControl:Bool { unicodeScalars.contains { $0.value<32 || $0.value==127 } } }

enum CodexRPC {
    static var executable: String? {
        let env=ProcessInfo.processInfo.environment
        var candidates=[env["CODEX_BIN"],"/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex","/Applications/Codex.app/Contents/Resources/codex",NSHomeDirectory()+"/.local/bin/codex","/opt/homebrew/bin/codex","/usr/local/bin/codex"].compactMap{$0}
        candidates += (env["PATH"] ?? "").split(separator:":").map{String($0)+"/codex"}
        return candidates.first{ FileManager.default.isExecutableFile(atPath:$0) }
    }
    static func quota() throws -> CodexQuota {
        guard let executable else{throw GroveError.message("未找到 Codex CLI。请安装或打开 Codex 后重试。")}
        let process=Process();process.executableURL=URL(fileURLWithPath:executable);process.arguments=["app-server"]
        let input=Pipe(),output=Pipe();process.standardInput=input;process.standardOutput=output;process.standardError=FileHandle.nullDevice
        try process.run()
        let timeout=DispatchWorkItem { if process.isRunning {process.terminate()} }
        DispatchQueue.global().asyncAfter(deadline:.now()+18,execute:timeout)
        defer { timeout.cancel();try? input.fileHandleForWriting.close();if process.isRunning {process.terminate()};process.waitUntilExit() }
        func send(_ value:[String:Any]) throws { var data=try JSONSerialization.data(withJSONObject:value);data.append(10);try input.fileHandleForWriting.write(contentsOf:data) }
        try send(["id":1,"method":"initialize","params":["clientInfo":["name":"cyan-grove","version":"0.4.0"]]])
        var pending=Data()
        while true {
            let chunk=output.fileHandleForReading.availableData
            if chunk.isEmpty {throw GroveError.message("Codex 额度读取超时或服务已退出；保留上次结果。")}
            pending.append(chunk)
            guard pending.count<4*1024*1024 else{throw GroveError.message("额度响应异常。")}
            while let end=pending.firstIndex(of:10) {
                let line=Data(pending.prefix(upTo:end));pending.removeSubrange(...end)
                guard let value=(try? JSONSerialization.jsonObject(with:line)) as? [String:Any],let id=value["id"] as? Int else{continue}
                if value["error"] != nil {throw GroveError.message("Codex 未能返回额度，请确认当前登录状态。")}
                if id==1 {try send(["method":"initialized"]);try send(["id":2,"method":"account/rateLimits/read"])}
                if id==2,let result=value["result"] as? [String:Any] {return try CodexQuota.parse(result)}
            }
        }
    }
}

@MainActor final class CodexStore: ObservableObject {
    @Published var quota:CodexQuota?=CodexLocalData.load(CodexQuota.self,"quota.json")
    @Published var quotaError:String?
    @Published var observations:[QuotaObservation] = []
    var todayObserved:Double {
        let today=CodexUsage.day(.now)
        return zip(observations,observations.dropFirst()).reduce(0) { sum,pair in
            let (a,b)=pair
            guard CodexUsage.day(a.date)==today, CodexUsage.day(b.date)==today else{return sum}
            let used = a.resets == b.resets ? max(0,a.remaining-b.remaining) : max(0,100-b.remaining)
            return sum+used
        }
    }
    var suggestedDaily:Double? {
        guard let w=quota?.preferredWindow,w.minutes==10080,let reset=w.resets else{return nil}
        return w.remaining/max(1,ceil(reset.timeIntervalSinceNow/86400))
    }
    @Published var usage=CodexUsage()
    @Published var usageError:String?
    @Published var quotaLoading=false
    @Published var scanning=false
    @Published var plan:Double { didSet{UserDefaults.standard.set(plan,forKey:"cyan.codex.dailyPlan")} }
    @Published var feedback:String {didSet{UserDefaults.standard.set(feedback,forKey:"cyan.comfort."+CodexUsage.day(.now))}}
    private var quotaTimer:Timer?,usageTimer:Timer?
    init() {plan=UserDefaults.standard.object(forKey:"cyan.codex.dailyPlan") as? Double ?? 10;feedback=UserDefaults.standard.string(forKey:"cyan.comfort."+CodexUsage.day(.now)) ?? "未记录"
        observations=CodexLocalData.load([QuotaObservation].self,"quota-history.json") ?? []
        if observations.isEmpty {
            let url=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("app.codexcockpit.desktop/runtime-state.json")
            let iso=ISO8601DateFormatter();iso.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
            let plain=ISO8601DateFormatter()
            if let size=(try? url.resourceValues(forKeys:[.fileSizeKey]))?.fileSize,size<2*1024*1024,let data=try? Data(contentsOf:url),let object=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],let history=object["history"] as? [[String:Any]] {
                observations=history.compactMap { row in
                    guard row["provider"] as? String == "codex",row["status"] as? String == "ok",row["metricKind"] as? String == "percent",let metric=(row["metric"] as? NSNumber)?.doubleValue,let stamp=row["capturedAt"] as? String,let date=iso.date(from:stamp) ?? plain.date(from:stamp) else{return nil}
                    let reset=(row["resetsAt"] as? String).flatMap{iso.date(from:$0) ?? plain.date(from:$0)}
                    return QuotaObservation(date:date,remaining:max(0,min(100,metric)),resets:reset)
                }.sorted{$0.date<$1.date}
            }
        }
    }
    func start() {
        Task {await refreshQuota()};Task {await scan()}
        quotaTimer=Timer.scheduledTimer(withTimeInterval:300,repeats:true){[weak self] _ in Task{@MainActor in await self?.refreshQuota()}}
        usageTimer=Timer.scheduledTimer(withTimeInterval:60,repeats:true){[weak self] _ in Task{@MainActor in await self?.scan()}}
    }
    func refreshQuota() async {
        guard !quotaLoading else{return};quotaLoading=true;defer{quotaLoading=false}
        do {let result=try await Task.detached(priority:.utility){try CodexRPC.quota()}.value;quota=result;quotaError=nil;try? CodexLocalData.save(result,"quota.json")
            if let window=result.preferredWindow, window.minutes==10080 {
                observations=Array((observations+[QuotaObservation(date:result.date,remaining:window.remaining,resets:window.resets)]).suffix(10000))
                try? CodexLocalData.save(observations,"quota-history.json")
            }}
        catch{quotaError=error.localizedDescription}
    }
    func scan() async {
        guard !scanning else{return};scanning=true;defer{scanning=false}
        do{let result=try await Task.detached(priority:.utility){try CodexLocalData.scan()}.value;usage=result;usageError=nil}
        catch{usageError=error.localizedDescription}
    }
}
