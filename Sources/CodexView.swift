import SwiftUI
import AppKit
import Charts
struct CodexDashboardView:View {
    @ObservedObject var store:CodexStore
    var p:GrovePalette
    @GroveState private var range="week"
    @GroveState private var kind="task"
    @GroveState private var selected=Set<String>()
    @GroveState private var selectedDay:String?
    @GroveState private var exportNotice:String?
    var rows:[UsageRow]{store.usage.rows(range:range,kind:kind,selectedDay:selectedDay)}
    var body:some View {
        VStack(alignment:.leading,spacing:24){
            HStack(alignment:.top){SectionHeading(eyebrow:"CODEX / PERSONAL COCKPIT",title:"心里有数，放心去做。",subtitle:"官方额度与本机 Token 用量分开记录。");Spacer();Button{Task{await store.refreshQuota();await store.scan()}}label:{Label(store.quotaLoading || store.scanning ? "更新中":"刷新",systemImage:"arrow.clockwise")}.disabled(store.quotaLoading || store.scanning)}
            if let error=store.quotaError {status(error)}
            quotaCards
            planning
            if let error=store.usageError {status(error)}
            quotaTrend
            usageSection
            calendar
            if let exportNotice {Text(exportNotice).font(.system(size:11)).foregroundStyle(p.accent)}
            Text("参考 Codex Cockpit 的本机统计功能 · 金额使用其 2026-10-12 离线价格表估算，不是订阅账单。未知模型或缺少计价上下文时保留未知。日期采用本机自然日。仅保存元数据与用量；不上传会话。").font(.system(size:10)).foregroundStyle(p.secondary).lineSpacing(5)
        }.onChange(of:range){_,_ in selected.removeAll();selectedDay=nil}.onChange(of:kind){_,_ in selected.removeAll()}.onChange(of:selectedDay){_,_ in selected.removeAll()}
    }
    var quotaCards:some View {
        VStack(alignment:.leading,spacing:16){
            HStack{Label("官方额度",systemImage:"sparkles").font(.system(size:15,weight:.semibold));Spacer();if let q=store.quota {Text([q.plan?.uppercased(),q.resetCredits.map{"可用重置 \($0) 次"}].compactMap{$0}.joined(separator:" · ")).font(.system(size:10)).foregroundStyle(p.secondary)}}
            if let q=store.quota {
                ForEach(q.windows){w in HStack(spacing:24){ZStack{Circle().stroke(p.soft,lineWidth:8);Circle().trim(from:0,to:w.remaining/100).stroke(p.accent,style:StrokeStyle(lineWidth:8,lineCap:.round)).rotationEffect(.degrees(-90));Text(SystemReading.percent(w.remaining)).font(.system(size:20,weight:.medium,design:.rounded))}.frame(width:84,height:84);VStack(alignment:.leading,spacing:8){Text(w.title).font(.system(size:14,weight:.semibold));Text("剩余 \(SystemReading.percent(w.remaining)) · 已用 \(SystemReading.percent(w.used))").font(.system(size:11)).foregroundStyle(p.secondary);Text(w.resets.map{"重置于 "+$0.formatted(date:.abbreviated,time:.shortened)} ?? "重置时间未知").font(.system(size:10)).foregroundStyle(p.secondary)};Spacer()}}
                Text("更新于 \(q.date.formatted(date:.abbreviated,time:.shortened))\(Date().timeIntervalSince(q.date)>600 ? " · 缓存，等待刷新":"")").font(.system(size:10)).foregroundStyle(p.secondary)
            } else {Text(store.quotaLoading ? "正在通过本机 Codex 读取…":"暂无可用额度，请确认 Codex 已登录。").font(.system(size:12)).foregroundStyle(p.secondary)}
        }.padding(24).frame(maxWidth:.infinity,alignment:.leading).background(p.card,in:RoundedRectangle(cornerRadius:20))
    }
    var planning:some View {
        VStack(alignment:.leading,spacing:16){HStack{Label("自己的使用节奏",systemImage:"leaf").font(.system(size:15,weight:.semibold));Spacer();Text("今日计划 \(Int(store.plan))% 周额度").font(.system(size:11)).foregroundStyle(p.accent)};HStack{Text(String(format:"今日已观测消耗 %.1f%%",store.todayObserved)).font(.system(size:12,weight:.medium));Spacer();if let suggested=store.suggestedDaily{Text(String(format:"余量均摊约 %.1f%% / 天",suggested)).font(.system(size:10)).foregroundStyle(p.secondary)}};ProgressView(value:min(store.todayObserved,store.plan),total:store.plan).tint(p.accent);Slider(value:$store.plan,in:1...100,step:1).tint(p.accent);HStack{Text("今天用起来").font(.system(size:11));Picker("舒适度",selection:$store.feedback){Text("未记录").tag("未记录");Text("紧张").tag("紧张");Text("刚好").tag("刚好");Text("宽裕").tag("宽裕")}.pickerStyle(.segmented).frame(width:260);Spacer()};Text("计划是个人目标。已观测消耗是采样下界，缺失时段不做推算；舒适度按日保存。").font(.system(size:10)).foregroundStyle(p.secondary)}.padding(24).background(p.hero,in:RoundedRectangle(cornerRadius:20))
    }
    var quotaTrend:some View {
        VStack(alignment:.leading,spacing:16){
            HStack{Text("额度走势").font(.system(size:15,weight:.semibold));Spacer();Text("最近 96 次观测").font(.system(size:10)).foregroundStyle(p.secondary)}
            if store.observations.isEmpty {Text("额度读取后开始记录。").font(.system(size:11)).foregroundStyle(p.secondary)}
            else {
                Chart(Array(store.observations.suffix(96))) { point in
                    LineMark(x:.value("时间",point.date),y:.value("剩余",point.remaining)).foregroundStyle(p.accent)
                    PointMark(x:.value("时间",point.date),y:.value("剩余",point.remaining)).foregroundStyle(p.accent).symbolSize(8)
                }.chartYScale(domain:0...100).frame(height:130)
            }
            Text("保留本机 Cockpit 已有观测；新记录每 5 分钟更新一次。").font(.system(size:10)).foregroundStyle(p.secondary)
        }.padding(24).background(p.card,in:RoundedRectangle(cornerRadius:20))
    }
    var usageSection:some View {
        VStack(alignment:.leading,spacing:18){
            HStack{Text("本机用量").font(.system(size:16,weight:.semibold));Spacer();Picker("时间范围",selection:$range){Text("今天").tag("today");Text("7 天").tag("week");Text("30 天").tag("month");Text("全部").tag("all")}.pickerStyle(.segmented).frame(width:260)}
            if let selectedDay {HStack{Label(selectedDay,systemImage:"calendar");Button("清除日期筛选"){self.selectedDay=nil}}.font(.system(size:11))}
            let total=store.usage.total(range:range,selectedDay:selectedDay)
            HStack(spacing:12){GroveTile(title:"Token 合计",value:store.usage.events.isEmpty ? "—":short(total.tokens.total),detail:"缓存已含在输入中",icon:"number",p:p);GroveTile(title:"缓存命中",value:total.tokens.input>0 ? SystemReading.percent(Double(total.tokens.cached)/Double(total.tokens.input)*100):"—",detail:short(total.tokens.cached)+" cached tokens",icon:"shippingbox",p:p);GroveTile(title:"API 等价估算",value:store.usage.events.isEmpty ? "—":cost(total.cost),detail:"美元 · 参考价，非账单",icon:"dollarsign",p:p)}
            HStack{Picker("分组",selection:$kind){Text("按任务").tag("task");Text("按模型").tag("model");Text("按项目").tag("project")}.pickerStyle(.segmented).frame(width:260);Spacer();Button("导出小票 PNG"){exportReceipt()}.disabled(selected.isEmpty)}
            if store.scanning && store.usage.events.isEmpty {ProgressView("正在扫描本机会话…").padding()}
            else if rows.isEmpty {Text("所选范围暂无可读取的用量事件。").font(.system(size:12)).foregroundStyle(p.secondary).padding(.vertical,20)}
            ForEach(rows.prefix(80)){row in
                HStack(spacing:12){Toggle(row.title,isOn:Binding(get:{selected.contains(row.id)},set:{if $0{selected.insert(row.id)}else{selected.remove(row.id)}})).labelsHidden().toggleStyle(.checkbox);VStack(alignment:.leading,spacing:5){Text(row.title).font(.system(size:12,weight:.medium)).lineLimit(1);Text(row.detail.isEmpty ? "输入 \(short(row.total.tokens.input)) · 输出 \(short(row.total.tokens.output))":"\(row.detail) · 输入 \(short(row.total.tokens.input)) · 输出 \(short(row.total.tokens.output))").font(.system(size:10)).foregroundStyle(p.secondary).lineLimit(1)};Spacer();VStack(alignment:.trailing,spacing:5){Text(short(row.total.tokens.total)).font(.system(size:13,weight:.medium,design:.rounded));Text(cost(row.total.cost)).font(.system(size:10)).foregroundStyle(p.secondary)}}.padding(.vertical,9)
                Divider().overlay(p.line)
            }
            if rows.count>80 {Text("当前显示前 80 项，汇总包含全部 \(rows.count) 项。").font(.system(size:10)).foregroundStyle(p.secondary)}
            Text(store.usage.date == .distantPast ? "等待扫描":"\(store.usage.sessions.count) 份会话 · \(store.usage.partial ? "部分覆盖，可能含截断、计数重置或继承记录":"扫描完成") · \(store.usage.date.formatted(date:.omitted,time:.shortened))").font(.system(size:10)).foregroundStyle(p.secondary)
        }.padding(24).background(p.card,in:RoundedRectangle(cornerRadius:20))
    }
    var calendar:some View {
        let days=(0..<91).reversed().map{CodexUsage.day(Calendar.current.date(byAdding:.day,value:-$0,to:Date())!)}
        let daily=store.usage.daily,peak=max(1,daily.values.map{$0.tokens.total}.max() ?? 1)
        return VStack(alignment:.leading,spacing:16){HStack{Text("用量日历").font(.system(size:15,weight:.semibold));Spacer();Text("最近 91 天 · 点击日期筛选").font(.system(size:10)).foregroundStyle(p.secondary)};LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:6),count:13),spacing:6){ForEach(days,id:\.self){day in let tokens=daily[day]?.tokens.total ?? 0;Button{selectedDay=selectedDay==day ? nil:day}label:{RoundedRectangle(cornerRadius:4).fill(tokens==0 ? p.soft:p.accent.opacity(0.25+0.75*Double(tokens)/Double(peak))).frame(height:23).overlay(RoundedRectangle(cornerRadius:4).stroke(selectedDay==day ? p.text:.clear,lineWidth:2))}.buttonStyle(.plain).help("\(day) · \(short(tokens)) tokens").accessibilityLabel("\(day)，\(tokens) tokens")}};Text("按行从早到晚排列；记录缺失时，空格不代表实际用量为零。").font(.system(size:10)).foregroundStyle(p.secondary)}.padding(24).background(p.card,in:RoundedRectangle(cornerRadius:20))
    }
    func status(_ message:String)->some View{Label(message,systemImage:"exclamationmark.circle").font(.system(size:11)).foregroundStyle(.orange).padding(14).frame(maxWidth:.infinity,alignment:.leading).background(p.card,in:RoundedRectangle(cornerRadius:12))}
    func short(_ n:Int)->String {if n>=1_000_000{return String(format:"%.2fM",Double(n)/1_000_000)};if n>=1_000{return String(format:"%.1fK",Double(n)/1_000)};return String(n)}
    func cost(_ n:Double?)->String {n.map{String(format:"$%.2f",$0)} ?? "未知"}
    @MainActor func exportReceipt(){
        let chosen=rows.filter{selected.contains($0.id)}
        let panel=NSSavePanel();panel.nameFieldStringValue="Cyan-Grove-\(CodexUsage.day(.now)).png";panel.allowedContentTypes=[.png]
        guard panel.runModal() == .OK,let url=panel.url else{return}
        let renderer=ImageRenderer(content:UsageReceipt(rows:chosen,date:CodexUsage.day(.now),period:selectedDay ?? ["today":"今天","week":"最近 7 天","month":"最近 30 天","all":"全部记录"][range] ?? range));renderer.scale=2
        guard let image=renderer.nsImage,let tiff=image.tiffRepresentation,let bitmap=NSBitmapImageRep(data:tiff),let data=bitmap.representation(using:.png,properties:[:]) else{exportNotice="无法生成小票";return}
        do{try data.write(to:url);exportNotice="小票已保存到 \(url.lastPathComponent)"}catch{exportNotice="保存失败，请选择可写入的位置。"}
    }
}
struct UsageReceipt:View {
    var rows:[UsageRow];var date:String;var period:String = "所选记录"
    var receiptCost:String {
        guard rows.allSatisfy({$0.total.cost != nil}) else{return "金额合计：未知"}
        return String(format:"估算合计  $%.4f",rows.reduce(0){$0+($1.total.cost ?? 0)})
    }
    var body:some View {
        VStack(alignment:.leading,spacing:16){Text("CYAN GROVE").font(.system(size:23,weight:.bold,design:.monospaced));Text("CODEX / LOCAL USAGE").font(.system(size:10,design:.monospaced));Text("生成于 "+date+" · "+period).font(.system(size:11));Divider();ForEach(rows){row in VStack(alignment:.leading,spacing:5){Text(row.title).font(.system(size:12,weight:.medium)).fixedSize(horizontal:false,vertical:true);HStack{Text("\(row.total.tokens.total) tokens");Spacer();Text(row.total.cost.map{String(format:"$%.4f",$0)} ?? "未知")}.font(.system(size:11,design:.monospaced))}};Divider();Text("TOTAL  \(rows.reduce(0){$0+$1.total.tokens.total}) tokens").font(.system(size:14,weight:.semibold,design:.monospaced));Text(receiptCost).font(.system(size:16,weight:.semibold,design:.monospaced));Text("API 等价估算 · 非订阅账单\n来源：本机 Codex 用量事件").font(.system(size:10)).foregroundStyle(.secondary)}.padding(30).frame(width:430).foregroundStyle(Color(hex:"253B30")).background(Color(hex:"FAF9F3")).environment(\.colorScheme,.light)
    }
}
