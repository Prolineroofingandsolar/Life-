import SwiftUI

// MARK: - Muscle Recovery Map
// Interactive front/back body map. Each muscle is tinted by how recently it was
// trained (fresh → green, fatigued → red), driven by AppState.daysSinceLastTrained.
// Muscle silhouettes are SVG paths traced over the 640×1200 body illustration.

struct MuscleRecoveryMapView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var showBack = false
    @State private var selected: MuscleGroup?

    // Palette (from the design)
    private let bg      = Color(hex: "#0E1116")
    private let card    = Color(hex: "#171A21")
    private let stroke  = Color(hex: "#262B34")
    private let subtext = Color(hex: "#8B919C")
    private let dim     = Color(hex: "#6A7080")
    private let green   = Color(hex: "#2FB36B")
    private let gold    = Color(hex: "#E8C84A")
    private let orange  = Color(hex: "#F2933C")
    private let red     = Color(hex: "#EC4D4D")

    private var groups: [MuscleGroup] { showBack ? MuscleGroup.back : MuscleGroup.front }

    // MARK: Recovery math (from real app data)

    private func fatigue(_ g: MuscleGroup) -> Int {
        guard let m = g.appMuscle, let days = appState.daysSinceLastTrained(muscle: m) else { return 0 }
        switch days {
        case 0: return 85
        case 1: return 55
        case 2: return 30
        case 3: return 15
        default: return 8
        }
    }

    private func color(_ fat: Int) -> Color {
        if fat >= 70 { return red }
        if fat >= 45 { return orange }
        if fat >= 25 { return gold }
        return green
    }

    private func statusLabel(_ fat: Int) -> String {
        if fat >= 70 { return "Fatigued" }
        if fat >= 45 { return "Recovering" }
        if fat >= 25 { return "Light" }
        return "Fresh"
    }

    private func lastTrained(_ g: MuscleGroup) -> String {
        guard let m = g.appMuscle, let d = appState.daysSinceLastTrained(muscle: m) else { return "—" }
        switch d {
        case 0: return "Today"
        case 1: return "Yesterday"
        default: return "\(d)d ago"
        }
    }

    private func freshIn(_ g: MuscleGroup) -> String {
        let fat = fatigue(g)
        guard fat >= 25, let m = g.appMuscle, let d = appState.daysSinceLastTrained(muscle: m) else { return "Ready" }
        let remaining = Swift.max(1, 2 - d)
        return "~\(remaining)d"
    }

    private func exercises(_ g: MuscleGroup) -> [String] {
        guard let m = g.appMuscle else { return [] }
        return appState.exercises.filter { $0.muscle == m }.prefix(6).map(\.name)
    }

    private var readiness: Int {
        let all = MuscleGroup.allUnique
        guard !all.isEmpty else { return 100 }
        let avg = all.map { fatigue($0) }.reduce(0, +) / all.count
        return Swift.max(0, Swift.min(100, 100 - avg))
    }

    private var ringColor: Color {
        readiness >= 65 ? green : (readiness >= 40 ? orange : red)
    }

    private var subtitle: String {
        if let s = appState.recentFinishedSessions(limit: 1).first, let fin = s.finishedAt {
            return "\(s.name) · \(relative(fin))"
        }
        return "No recent workouts"
    }

    private func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }

    private var needsRecovery: [MuscleGroup] {
        MuscleGroup.allUnique
            .map { ($0, fatigue($0)) }
            .filter { $0.1 >= 40 }
            .sorted { $0.1 > $1.1 }
            .prefix(4)
            .map { $0.0 }
    }

    private var freshCount: Int {
        MuscleGroup.allUnique.filter { fatigue($0) < 25 }.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    toggle
                    bodyMap
                    legend
                    if let sel = selected { detailPanel(sel) } else { needsRecoveryPanel }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 20)
            }
            .background(bg.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.foregroundColor(green)
                }
            }
            .toolbarBackground(bg, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("TRAIN · RECOVERY")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(2.5)
                    .foregroundColor(dim)
                Text("Recovery")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(subtext)
            }
            Spacer()
            VStack(spacing: 3) {
                ZStack {
                    Circle().stroke(Color(hex: "#23272F"), lineWidth: 6).frame(width: 58, height: 58)
                    Circle()
                        .trim(from: 0, to: CGFloat(readiness) / 100)
                        .stroke(ringColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 58, height: 58)
                    Text("\(readiness)")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                Text("RECOVERED")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.5)
                    .foregroundColor(dim)
            }
        }
    }

    // MARK: Front/Back toggle

    private var toggle: some View {
        HStack(spacing: 4) {
            toggleButton("FRONT", active: !showBack) { withAnimation(.spring(response: 0.3)) { showBack = false; selected = nil } }
            toggleButton("BACK", active: showBack) { withAnimation(.spring(response: 0.3)) { showBack = true; selected = nil } }
        }
        .padding(4)
        .background(card)
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color(hex: "#23272F"), lineWidth: 1))
        .cornerRadius(13)
    }

    private func toggleButton(_ title: String, active: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .tracking(1)
                .foregroundColor(active ? .white : Color(hex: "#7A808C"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(active ? Color(hex: "#2A2F3A") : Color.clear)
                .cornerRadius(9)
        }
        .buttonStyle(.plain)
    }

    // MARK: Body map

    private var bodyMap: some View {
        ZStack {
            Image(showBack ? "body-back" : "body-front")
                .resizable()
                .aspectRatio(640.0 / 1200.0, contentMode: .fit)

            GeometryReader { geo in
                let anySel = selected != nil
                ZStack {
                    ForEach(groups) { group in
                        let fat = fatigue(group)
                        let isSel = selected?.id == group.id
                        let op = !anySel ? 0.55 : (isSel ? 0.82 : 0.12)
                        MuscleShape(pathData: group.d, mirror: false)
                            .fill(color(fat).opacity(op))
                            .overlay {
                                if !group.centered {
                                    MuscleShape(pathData: group.d, mirror: true).fill(color(fat).opacity(op))
                                }
                            }
                            .contentShape(MuscleShape(pathData: group.d, mirror: false))
                            .onTapGesture {
                                HapticManager.selection()
                                withAnimation(.spring(response: 0.3)) {
                                    selected = (selected?.id == group.id) ? nil : group
                                }
                            }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .aspectRatio(640.0 / 1200.0, contentMode: .fit)
        .frame(maxHeight: 400)
        .frame(maxWidth: .infinity)
    }

    // MARK: Legend

    private var legend: some View {
        HStack(spacing: 14) {
            Text("Fresh").font(.system(size: 11)).foregroundColor(dim)
            HStack(spacing: 4) {
                ForEach([green, gold, orange, red], id: \.self) { c in
                    RoundedRectangle(cornerRadius: 4).fill(c).frame(width: 26, height: 7)
                }
            }
            Text("Fatigued").font(.system(size: 11)).foregroundColor(dim)
        }
    }

    // MARK: Detail panel

    private func detailPanel(_ g: MuscleGroup) -> some View {
        let fat = fatigue(g)
        let c = color(fat)
        let exs = exercises(g)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(g.name).font(.system(size: 24, weight: .bold)).foregroundColor(.white)
                    Text(exs.isEmpty ? "No exercises logged" : "Worked by \(exs.count) exercise\(exs.count == 1 ? "" : "s")")
                        .font(.system(size: 13)).foregroundColor(subtext)
                }
                Spacer()
                Text(statusLabel(fat))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(c)
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(c.opacity(0.13)).cornerRadius(9)
                Button { withAnimation { selected = nil } } label: {
                    Image(systemName: "xmark").font(.system(size: 13)).foregroundColor(subtext)
                        .frame(width: 30, height: 30)
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color(hex: "#2A2F3A"), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
            }

            HStack {
                Text("FATIGUE").font(.system(size: 12, weight: .medium)).tracking(1.5).foregroundColor(dim)
                Spacer()
                Text("\(fat)%").font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundColor(c)
            }
            .padding(.top, 16).padding(.bottom, 7)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6).fill(bg).frame(height: 9)
                    RoundedRectangle(cornerRadius: 6).fill(c)
                        .frame(width: geo.size.width * CGFloat(fat) / 100, height: 9)
                }
            }
            .frame(height: 9)

            HStack(spacing: 10) {
                miniStat("LAST TRAINED", lastTrained(g), .white)
                miniStat("FRESH IN", freshIn(g), freshIn(g) == "Ready" ? green : .white)
            }
            .padding(.top, 16)

            if !exs.isEmpty {
                Text("WORKED BY").font(.system(size: 11, weight: .medium)).tracking(1.5).foregroundColor(dim)
                    .padding(.top, 16).padding(.bottom, 9)
                FlowChips(items: exs, textColor: Color(hex: "#C7CCD4"), bg: bg, border: stroke)
            }
        }
        .padding(18)
        .background(card)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(stroke, lineWidth: 1))
        .cornerRadius(20)
    }

    private func miniStat(_ label: String, _ value: String, _ valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 11, weight: .medium)).tracking(1).foregroundColor(dim)
            Text(value).font(.system(size: 18, weight: .semibold, design: .rounded)).foregroundColor(valueColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(bg).cornerRadius(13)
    }

    // MARK: Needs-recovery panel

    private var needsRecoveryPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Needs recovery").font(.system(size: 17, weight: .semibold)).foregroundColor(.white)
                Spacer()
                Text("Tap a muscle ↑").font(.system(size: 13)).foregroundColor(dim)
            }
            .padding(.bottom, 6)

            if needsRecovery.isEmpty {
                Text("Everything's fresh — good to train.")
                    .font(.system(size: 14)).foregroundColor(subtext)
                    .padding(.vertical, 10)
            } else {
                ForEach(needsRecovery) { g in
                    let fat = fatigue(g)
                    HStack(spacing: 11) {
                        Circle().fill(color(fat)).frame(width: 10, height: 10)
                        Text(g.name).font(.system(size: 15, weight: .medium)).foregroundColor(.white)
                        Spacer()
                        Text(statusLabel(fat)).font(.system(size: 13)).foregroundColor(subtext)
                        Text("\(fat)%").font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(color(fat)).frame(minWidth: 38, alignment: .trailing)
                    }
                    .padding(.vertical, 9)
                    .overlay(Rectangle().fill(Color(hex: "#21262E")).frame(height: 1), alignment: .top)
                }
            }

            HStack(spacing: 8) {
                Circle().fill(green).frame(width: 10, height: 10)
                (Text("\(freshCount) groups ").foregroundColor(green).font(.system(size: 14, weight: .semibold))
                 + Text("fresh & ready to train").foregroundColor(subtext).font(.system(size: 14)))
            }
            .padding(.top, 14)
            .overlay(Rectangle().fill(Color(hex: "#21262E")).frame(height: 1), alignment: .top)
            .padding(.top, 14)
        }
        .padding(18)
        .background(card)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(stroke, lineWidth: 1))
        .cornerRadius(20)
    }
}

// MARK: - Flow chips

private struct FlowChips: View {
    let items: [String]
    let textColor: Color
    let bg: Color
    let border: Color

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.system(size: 13))
                        .foregroundColor(textColor)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(bg)
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(border, lineWidth: 1))
                        .cornerRadius(9)
                        .fixedSize()
                }
            }
        }
    }
}

// MARK: - Muscle shape (SVG path → SwiftUI Path, scaled to the 640×1200 viewBox)

struct MuscleShape: Shape {
    let pathData: String
    var mirror: Bool = false

    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 640.0
        let sy = rect.height / 1200.0
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            let mx = mirror ? (640.0 - x) : x
            return CGPoint(x: rect.minX + mx * sx, y: rect.minY + y * sy)
        }

        var path = Path()
        let scanner = SVGPathScanner(pathData)
        var cmd: Character = " "
        while let token = scanner.nextCommandOrNumber() {
            switch token {
            case .command(let c):
                cmd = c
                if c == "Z" || c == "z" { path.closeSubpath() }
            case .number(let first):
                switch cmd {
                case "M", "m":
                    if let y = scanner.nextNumber() { path.move(to: pt(first, y)) }
                    cmd = "L" // subsequent pairs are line-to
                case "L", "l":
                    if let y = scanner.nextNumber() { path.addLine(to: pt(first, y)) }
                case "Q", "q":
                    if let cy = scanner.nextNumber(), let ex = scanner.nextNumber(), let ey = scanner.nextNumber() {
                        path.addQuadCurve(to: pt(ex, ey), control: pt(first, cy))
                    }
                default:
                    break
                }
            }
        }
        return path
    }
}

// Minimal tokenizer for the M/L/Q/Z path subset used by the muscle geometry.
private final class SVGPathScanner {
    enum Token { case command(Character); case number(CGFloat) }
    private let chars: [Character]
    private var i = 0
    init(_ s: String) { chars = Array(s) }

    func nextCommandOrNumber() -> Token? {
        skipSeparators()
        guard i < chars.count else { return nil }
        let c = chars[i]
        if c.isLetter { i += 1; return .command(c) }
        if let n = readNumber() { return .number(n) }
        return nil
    }

    func nextNumber() -> CGFloat? {
        skipSeparators()
        return readNumber()
    }

    private func skipSeparators() {
        while i < chars.count, chars[i] == " " || chars[i] == "," || chars[i] == "\n" || chars[i] == "\t" { i += 1 }
    }

    private func readNumber() -> CGFloat? {
        skipSeparators()
        var s = ""
        if i < chars.count, chars[i] == "-" { s.append(chars[i]); i += 1 }
        while i < chars.count, chars[i].isNumber || chars[i] == "." { s.append(chars[i]); i += 1 }
        return Double(s).map { CGFloat($0) }
    }
}

// MARK: - Muscle group data (traced over the 640×1200 illustration)

struct MuscleGroup: Identifiable {
    let id: String          // stable id incl. side (e.g. "front-chest")
    let key: String         // muscle key (chest, quads, …)
    let name: String
    let d: String           // SVG path
    let centered: Bool      // true = single centered shape; false = mirror to both sides
    let appMuscle: String?  // maps to AppState muscle strings for recovery lookup

    static let front: [MuscleGroup] = [
        .init(id: "front-traps",     key: "traps",     name: "Traps",     d: G.trapsF,   centered: false, appMuscle: "Back"),
        .init(id: "front-shoulders", key: "shoulders", name: "Shoulders", d: G.deltF,    centered: false, appMuscle: "Shoulders"),
        .init(id: "front-chest",     key: "chest",     name: "Chest",     d: G.pecF,     centered: false, appMuscle: "Chest"),
        .init(id: "front-biceps",    key: "biceps",    name: "Biceps",    d: G.bicepF,   centered: false, appMuscle: "Biceps"),
        .init(id: "front-forearms",  key: "forearms",  name: "Forearms",  d: G.forearmF, centered: false, appMuscle: nil),
        .init(id: "front-abs",       key: "abs",       name: "Abs",       d: G.abs,      centered: true,  appMuscle: "Core"),
        .init(id: "front-obliques",  key: "obliques",  name: "Obliques",  d: G.obliqueF, centered: false, appMuscle: "Core"),
        .init(id: "front-quads",     key: "quads",     name: "Quads",     d: G.quadF,    centered: false, appMuscle: "Legs"),
        .init(id: "front-calves",    key: "calves",    name: "Calves",    d: G.calfF,    centered: false, appMuscle: "Calves"),
    ]

    static let back: [MuscleGroup] = [
        .init(id: "back-traps",      key: "traps",      name: "Traps",      d: G.trapsB,  centered: true,  appMuscle: "Back"),
        .init(id: "back-rearDelts",  key: "rearDelts",  name: "Rear Delts", d: G.rdeltB,  centered: false, appMuscle: "Shoulders"),
        .init(id: "back-lats",       key: "lats",       name: "Lats",       d: G.latB,    centered: false, appMuscle: "Back"),
        .init(id: "back-triceps",    key: "triceps",    name: "Triceps",    d: G.tricepB, centered: false, appMuscle: "Triceps"),
        .init(id: "back-forearms",   key: "forearms",   name: "Forearms",   d: G.forearmF,centered: false, appMuscle: nil),
        .init(id: "back-lowerBack",  key: "lowerBack",  name: "Lower Back", d: G.lowerB,  centered: true,  appMuscle: "Back"),
        .init(id: "back-glutes",     key: "glutes",     name: "Glutes",     d: G.gluteB,  centered: false, appMuscle: "Glutes"),
        .init(id: "back-hamstrings", key: "hamstrings", name: "Hamstrings", d: G.hamB,    centered: false, appMuscle: "Legs"),
        .init(id: "back-calves",     key: "calves",     name: "Calves",     d: G.calfB,   centered: false, appMuscle: "Calves"),
    ]

    /// Unique muscle keys across front+back (for readiness/aggregate stats).
    static let allUnique: [MuscleGroup] = {
        var seen = Set<String>()
        return (front + back).filter { seen.insert($0.key).inserted }
    }()

    private enum G {
        static let trapsF   = "M320,214 Q358,226 396,250 Q374,260 346,258 Q328,250 320,238 Z"
        static let deltF    = "M358,250 Q400,240 438,256 Q470,292 462,348 Q454,366 426,362 Q396,352 378,318 Q362,288 358,250 Z"
        static let pecF     = "M246,247 L260,250 L274,252 L291,257 L298,264 L306,273 L311,285 L313,295 L313,307 L313,326 L313,338 L310,351 L298,360 L286,365 L270,369 L253,369 L241,362 L233,355 L226,348 L217,333 L210,322 L202,310 L203,302 L210,290 L219,276 L229,262 L233,256 Z"
        static let bicepF   = "M442,362 Q472,360 486,392 Q490,435 482,475 Q470,490 456,486 Q444,452 440,408 Q440,382 442,362 Z"
        static let forearmF = "M452,490 Q486,488 502,516 Q506,560 494,600 Q484,618 470,614 Q458,596 454,554 Q450,520 452,490 Z"
        static let abs      = "M292,392 Q320,386 356,392 Q360,458 350,508 L342,545 Q333,576 320,628 Q309,576 298,545 L290,508 Q284,452 292,392 Z"
        static let obliqueF = "M357,396 Q390,404 404,432 Q408,495 392,536 Q378,550 364,544 L357,468 Z"
        static let quadF    = "M334,632 Q398,630 444,666 Q464,720 458,796 Q448,858 424,886 Q398,898 374,880 Q352,840 344,762 Q336,694 334,632 Z"
        static let calfF    = "M358,905 Q404,910 428,958 Q438,1015 426,1068 Q410,1086 392,1082 Q372,1068 364,1012 Q356,958 358,905 Z"
        static let trapsB   = "M320,188 Q358,200 392,250 Q380,300 350,330 Q335,340 320,340 Q305,340 290,330 Q260,300 248,250 Q282,200 320,188 Z"
        static let rdeltB   = "M356,250 Q405,234 442,260 Q470,302 458,362 Q442,384 408,378 Q378,368 366,324 Q356,284 356,250 Z"
        static let latB     = "M336,356 Q384,364 416,400 Q426,448 412,490 Q382,500 350,492 Q336,458 334,406 Z"
        static let tricepB  = "M442,362 Q472,360 486,392 Q490,435 482,475 Q470,490 456,486 Q444,452 440,408 Q440,382 442,362 Z"
        static let lowerB   = "M300,334 Q320,329 340,334 L342,470 Q330,492 320,494 Q310,492 298,470 L300,400 Z"
        static let gluteB   = "M326,500 Q392,498 422,536 Q436,580 420,618 Q392,640 350,632 Q328,612 324,564 Q322,530 326,500 Z"
        static let hamB     = "M330,638 Q400,635 442,676 Q456,730 448,790 Q436,818 405,820 Q372,812 350,770 Q332,710 330,638 Z"
        static let calfB    = "M352,824 Q412,832 436,890 Q448,956 432,1010 Q414,1032 392,1028 Q368,1012 360,950 Q350,890 352,824 Z"
    }
}
