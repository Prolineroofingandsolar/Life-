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

    // Palette — adapts to the system appearance instead of forcing dark mode.
    private let bg      = Color(.systemGroupedBackground)
    private let card    = Color(.secondarySystemGroupedBackground)
    private let stroke  = Color(.separator)
    private let subtext = Color(.secondaryLabel)
    private let dim     = Color(.tertiaryLabel)
    private let green   = Color(hex: "#2FB36B")
    private let gold    = Color(hex: "#E8C84A")
    private let orange  = Color(hex: "#F2933C")
    private let red     = Color(hex: "#EC4D4D")

    private var groups: [MuscleGroup] { showBack ? MuscleGroup.back : MuscleGroup.front }

    // MARK: Recovery math (from real app data)

    private func trainingInfo(_ g: MuscleGroup) -> AppState.MuscleTrainingInfo? {
        guard let m = g.appMuscle else { return nil }
        return appState.lastTrainingInfo(muscle: m)
    }

    /// Set-count baseline — meaningful from the very first session, with no
    /// training history required (a personal-best comparison alone collapses
    /// to "full effort" whenever the latest session happens to also be the
    /// only/heaviest one on record, which is exactly the case for anyone who
    /// hasn't logged much yet).
    private func setIntensity(_ sets: Int) -> Double {
        switch sets {
        case ..<3:   return 0.35
        case 3..<6:  return 0.6
        case 6..<10: return 0.85
        default:     return 1.0
        }
    }

    /// Blends the set-count baseline with this session's volume (sets ×
    /// weight moved) relative to the best single session ever recorded for
    /// this muscle, once there's actually a prior session to compare
    /// against. Falls back to the set-count baseline alone otherwise, so a
    /// light session reads as light from day one instead of only after
    /// enough history has built up.
    private func intensity(_ g: MuscleGroup, info: AppState.MuscleTrainingInfo) -> Double {
        let bySets = setIntensity(info.completedSets)
        guard let m = g.appMuscle else { return bySets }
        let best = appState.personalBestVolume(muscle: m, excludingSessionId: info.sessionId)
        guard best > 0 else { return bySets }
        let byVolume = Swift.min(1.0, info.volume / best)
        return (bySets + byVolume) / 2
    }

    /// Day-based fatigue for a muscle with the given full-recovery window:
    /// always high right after training, then tapers to a small residual
    /// floor by the time that muscle's own recovery window has elapsed —
    /// so a 1.5-day muscle (biceps) is back to baseline well before a
    /// 3-day one (legs, back).
    private func dayFatigue(daysAgo: Int, recoveryDays: Double) -> Double {
        guard daysAgo > 0 else { return 85 }
        let remaining = Swift.max(0, 1 - Double(daysAgo) / recoveryDays)
        return 8 + remaining * 77
    }

    private func fatigue(_ g: MuscleGroup) -> Int {
        guard let m = g.appMuscle, let info = trainingInfo(g) else { return 0 }
        let base = dayFatigue(daysAgo: info.daysAgo, recoveryDays: appState.recoveryDays(forMuscle: m))
        return Int((base * intensity(g, info: info)).rounded())
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
        guard let info = trainingInfo(g) else { return "—" }
        switch info.daysAgo {
        case 0: return "Today"
        case 1: return "Yesterday"
        default: return "\(info.daysAgo)d ago"
        }
    }

    private func freshIn(_ g: MuscleGroup) -> String {
        let fat = fatigue(g)
        guard fat >= 25, let m = g.appMuscle, let info = trainingInfo(g) else { return "Ready" }
        let remaining = Swift.max(1, Int(appState.recoveryDays(forMuscle: m).rounded(.up)) - info.daysAgo)
        return "~\(remaining)d"
    }

    /// The actual exercises, set counts, and weight moved from the muscle's
    /// most recent trained session (e.g. "Bicep Curls · 2 sets · 60kg"), not
    /// just the static list of exercises that target it.
    private func trainedExercises(_ g: MuscleGroup) -> [(name: String, sets: Int, volume: Double, kind: ExerciseKind)] {
        trainingInfo(g)?.exerciseBreakdown ?? []
    }

    /// "Bicep Curls · 2 sets · 60kg" — the weight figure is omitted for
    /// bodyweight/cardio exercises, where volume is a rep-count proxy rather
    /// than an actual load moved.
    private func chipLabel(_ ex: (name: String, sets: Int, volume: Double, kind: ExerciseKind)) -> String {
        let setsPart = "\(ex.sets) set\(ex.sets == 1 ? "" : "s")"
        guard ex.kind == .weight, ex.volume > 0 else { return "\(ex.name) · \(setsPart)" }
        let unit = appState.workoutSettings.weightUnit
        let displayVolume = WeightUnit.kg.convert(ex.volume, to: unit)
        return "\(ex.name) · \(setsPart) · \(Int(displayVolume))\(unit.label.lowercased())"
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
        }
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
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(subtext)
            }
            Spacer()
            VStack(spacing: 3) {
                ZStack {
                    Circle().stroke(stroke, lineWidth: 6).frame(width: 58, height: 58)
                    Circle()
                        .trim(from: 0, to: CGFloat(readiness) / 100)
                        .stroke(ringColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 58, height: 58)
                    Text("\(readiness)")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
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
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(stroke, lineWidth: 1))
        .cornerRadius(13)
    }

    private func toggleButton(_ title: String, active: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .tracking(1)
                .foregroundColor(active ? .white : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(active ? AppTheme.primary : Color.clear)
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
                        ForEach(Array(group.paths.enumerated()), id: \.offset) { _, d in
                            MuscleShape(pathData: d)
                                .fill(color(fat).opacity(op))
                                .contentShape(MuscleShape(pathData: d))
                                .onTapGesture {
                                    HapticManager.selection()
                                    withAnimation(.spring(response: 0.3)) {
                                        selected = (selected?.id == group.id) ? nil : group
                                    }
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
        let trained = trainedExercises(g)
        let totalSets = trained.reduce(0) { $0 + $1.sets }
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(g.name).font(.system(size: 24, weight: .bold)).foregroundColor(.primary)
                    Text(trained.isEmpty ? "No sets logged yet" : "\(totalSets) set\(totalSets == 1 ? "" : "s") across \(trained.count) exercise\(trained.count == 1 ? "" : "s")")
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
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color(.tertiarySystemFill), lineWidth: 1))
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
                miniStat("LAST TRAINED", lastTrained(g), .primary)
                miniStat("FRESH IN", freshIn(g), freshIn(g) == "Ready" ? green : .primary)
            }
            .padding(.top, 16)

            if !trained.isEmpty {
                Text("LAST SESSION").font(.system(size: 11, weight: .medium)).tracking(1.5).foregroundColor(dim)
                    .padding(.top, 16).padding(.bottom, 9)
                FlowChips(items: trained.map(chipLabel), textColor: Color.primary, bg: bg, border: stroke)
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
                Text("Needs recovery").font(.system(size: 17, weight: .semibold)).foregroundColor(.primary)
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
                        Text(g.name).font(.system(size: 15, weight: .medium)).foregroundColor(.primary)
                        Spacer()
                        Text(statusLabel(fat)).font(.system(size: 13)).foregroundColor(subtext)
                        Text("\(fat)%").font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(color(fat)).frame(minWidth: 38, alignment: .trailing)
                    }
                    .padding(.vertical, 9)
                    .overlay(Rectangle().fill(stroke).frame(height: 1), alignment: .top)
                }
            }

            HStack(spacing: 8) {
                Circle().fill(green).frame(width: 10, height: 10)
                (Text("\(freshCount) groups ").foregroundColor(green).font(.system(size: 14, weight: .semibold))
                 + Text("fresh & ready to train").foregroundColor(subtext).font(.system(size: 14)))
            }
            .padding(.top, 14)
            .overlay(Rectangle().fill(stroke).frame(height: 1), alignment: .top)
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
    let paths: [String]     // one or more traced SVG regions (drawn as-is)
    let appMuscle: String?  // maps to AppState muscle strings for recovery lookup

    static let front: [MuscleGroup] = [
        .init(id: "front-traps",     key: "traps",     name: "Traps",     paths: G.frontTraps,     appMuscle: "Back"),
        .init(id: "front-shoulders", key: "shoulders", name: "Shoulders", paths: G.frontShoulders, appMuscle: "Shoulders"),
        .init(id: "front-chest",     key: "chest",     name: "Chest",     paths: G.frontChest,     appMuscle: "Chest"),
        .init(id: "front-biceps",    key: "biceps",    name: "Biceps",    paths: G.frontBiceps,    appMuscle: "Biceps"),
        .init(id: "front-forearms",  key: "forearms",  name: "Forearms",  paths: G.frontForearms,  appMuscle: nil),
        .init(id: "front-abs",       key: "abs",       name: "Abs",       paths: G.frontAbs,       appMuscle: "Core"),
        .init(id: "front-obliques",  key: "obliques",  name: "Obliques",  paths: G.frontObliques,  appMuscle: "Core"),
        .init(id: "front-quads",     key: "quads",     name: "Quads",     paths: G.frontQuads,     appMuscle: "Legs"),
        .init(id: "front-calves",    key: "calves",    name: "Calves",    paths: G.frontCalves,    appMuscle: "Calves"),
    ]

    static let back: [MuscleGroup] = [
        .init(id: "back-traps",      key: "traps",      name: "Traps",      paths: G.backTraps,      appMuscle: "Back"),
        .init(id: "back-rearDelts",  key: "rearDelts",  name: "Rear Delts", paths: G.backRearDelts,  appMuscle: "Shoulders"),
        .init(id: "back-lats",       key: "lats",       name: "Lats",       paths: G.backLats,       appMuscle: "Back"),
        .init(id: "back-triceps",    key: "triceps",    name: "Triceps",    paths: G.backTriceps,    appMuscle: "Triceps"),
        .init(id: "back-forearms",   key: "forearms",   name: "Forearms",   paths: G.backForearms,   appMuscle: nil),
        .init(id: "back-lowerBack",  key: "lowerBack",  name: "Lower Back", paths: G.backLowerBack,  appMuscle: "Back"),
        .init(id: "back-glutes",     key: "glutes",     name: "Glutes",     paths: G.backGlutes,     appMuscle: "Glutes"),
        .init(id: "back-hamstrings", key: "hamstrings", name: "Hamstrings", paths: G.backHamstrings, appMuscle: "Legs"),
        .init(id: "back-calves",     key: "calves",     name: "Calves",     paths: G.backCalves,     appMuscle: "Calves"),
    ]

    /// Unique muscle keys across front+back (for readiness/aggregate stats).
    static let allUnique: [MuscleGroup] = {
        var seen = Set<String>()
        return (front + back).filter { seen.insert($0.key).inserted }
    }()

    // Custom shapes traced by the user in the Muscle Path Editor (640×1200, both sides explicit).
    private enum G {
        static let frontTraps = [
            "M279,195 L269,214 L255,221 L234,225 L209,233 L222,238 L231,240 L241,245 L258,249 L269,238 L274,226 L279,213 Z",
            "M430,235 L406,226 L380,219 L370,211 L363,195 L365,223 L371,233 L378,242 L383,249 L397,245 L413,240 Z",
        ]
        static let frontShoulders = [
            "M245,245 L233,242 L219,238 L207,235 L190,238 L178,245 L166,255 L157,269 L150,283 L147,297 L147,312 L149,324 L149,336 L164,319 L176,312 L188,309 L198,309 L205,302 L210,293 L215,283 L221,276 L227,264 L236,255 Z",
            "M395,245 L411,240 L423,238 L437,238 L449,240 L459,243 L469,250 L474,259 L483,267 L486,278 L490,290 L491,302 L493,315 L491,331 L476,319 L455,310 L443,307 L435,300 L431,288 L423,274 L414,262 L404,254 Z",
        ]
        static let frontChest = [
            "M246,247 L260,250 L274,252 L291,257 L298,264 L306,273 L311,285 L313,295 L313,307 L313,326 L313,338 L310,351 L298,360 L286,365 L270,369 L253,369 L241,362 L233,355 L226,348 L217,333 L210,322 L202,310 L203,302 L210,290 L219,276 L229,262 L233,256 Z",
            "M395,245 L402,252 L411,259 L418,273 L425,281 L440,307 L431,322 L421,338 L404,357 L390,367 L373,367 L359,367 L342,358 L332,351 L327,338 L327,319 L327,293 L329,281 L334,269 L346,261 L365,255 L377,250 Z",
        ]
        static let frontBiceps = [
            "M197,309 L205,321 L207,338 L203,351 L200,365 L193,381 L183,394 L171,405 L161,415 L149,422 L145,410 L138,379 L137,360 L142,343 L149,329 L167,315 L181,309 Z",
            "M440,309 L433,327 L433,348 L438,367 L445,379 L461,396 L476,411 L495,422 L497,405 L502,382 L503,362 L498,345 L490,331 L464,312 Z",
        ]
        static let frontForearms = [
            "M128,399 L130,408 L135,427 L135,442 L135,458 L143,439 L149,432 L161,423 L169,418 L166,441 L162,465 L155,482 L147,497 L138,509 L116,535 L125,509 L126,492 L116,518 L106,533 L95,545 L82,555 L85,533 L90,513 L95,492 L94,478 L97,461 L102,447 L107,432 L116,417 Z",
            "M473,420 L490,430 L502,447 L509,468 L514,492 L517,514 L522,530 L526,543 L509,519 L502,506 L491,494 L483,478 L478,458 L473,441 Z",
            "M512,398 L521,410 L529,423 L534,437 L541,458 L545,473 L546,490 L551,513 L553,531 L560,552 L550,549 L538,538 L529,523 L521,507 L514,492 L509,471 L505,454 L505,435 L507,418 Z",
        ]
        static let frontAbs = [
            "M274,384 L294,370 L306,362 L313,365 L318,372 L323,365 L334,365 L346,370 L366,381 L361,396 L359,408 L359,439 L358,540 L353,557 L347,571 L341,585 L323,609 L311,600 L301,586 L293,573 L287,561 L282,543 L279,519 L279,495 L281,454 L281,434 L281,415 Z",
        ]
        static let frontObliques = [
            "M207,319 L209,341 L210,355 L212,365 L214,375 L217,386 L221,396 L227,411 L231,422 L234,434 L234,453 L227,478 L229,494 L227,509 L224,521 L243,518 L255,511 L262,499 L263,487 L265,471 L267,456 L270,444 L272,422 L274,406 L272,394 L258,381 L246,372 L236,362 L227,351 L219,339 Z",
            "M365,413 L366,427 L370,442 L371,458 L375,473 L377,492 L383,507 L390,514 L402,519 L413,521 L413,499 L411,482 L407,461 L406,441 L407,422 L416,406 L419,391 L426,374 L430,358 L433,343 L433,322 L413,350 L401,363 L392,372 L380,381 L370,389 L366,398 Z",
        ]
        static let frontQuads = [
            "M226,531 L219,543 L217,566 L215,588 L207,607 L202,626 L198,650 L195,684 L195,705 L195,717 L198,730 L205,756 L210,773 L217,794 L226,811 L233,830 L236,816 L241,801 L245,780 L248,756 L246,737 L241,715 L236,696 L233,674 L231,641 L231,605 L231,579 Z",
            "M413,526 L413,557 L409,583 L411,615 L411,633 L411,646 L411,662 L406,681 L401,706 L397,727 L394,749 L395,777 L399,801 L402,821 L406,833 L414,809 L423,790 L430,770 L435,751 L442,723 L445,693 L443,670 L442,646 L433,619 L425,586 Z",
            "M226,526 L246,531 L255,538 L263,547 L269,557 L275,571 L281,583 L287,598 L293,612 L299,627 L306,634 L311,638 L311,653 L310,670 L308,686 L301,705 L294,730 L289,746 L286,761 L282,775 L279,790 L275,751 L272,729 L257,687 L245,657 L236,622 L233,609 L229,595 L229,574 L229,557 Z",
            "M411,530 L413,576 L411,595 L406,617 L399,641 L390,663 L380,689 L375,708 L370,727 L366,747 L365,765 L361,789 L351,749 L344,723 L337,698 L332,675 L329,653 L329,636 L337,633 L346,624 L347,610 L354,595 L363,579 L371,555 L380,540 L394,530 Z",
            "M399,845 L392,816 L390,794 L390,768 L392,751 L394,734 L399,715 L404,694 L409,665 L411,643 L411,621 L409,600 L402,636 L395,655 L387,672 L377,694 L371,727 L365,749 L363,766 L370,794 L377,809 L383,825 Z",
            "M241,847 L250,816 L251,801 L251,771 L248,754 L246,734 L241,711 L234,689 L233,665 L229,643 L229,622 L229,603 L231,588 L236,614 L238,634 L243,646 L250,662 L255,684 L267,717 L272,737 L277,763 L275,777 L269,795 L260,818 L251,833 Z",
        ]
        static let frontCalves = [
            "M257,867 L262,902 L262,926 L258,945 L253,960 L245,979 L238,1005 L234,1023 L233,1039 L227,1013 L227,984 L227,965 L224,945 L227,924 L231,905 L239,888 Z",
            "M409,1042 L414,977 L416,941 L413,921 L409,900 L401,888 L392,876 L383,867 L378,885 L378,914 L378,931 L382,950 L389,967 L395,984 L401,1003 Z",
            "M186,919 L198,900 L210,890 L214,915 L219,934 L219,950 L219,969 L217,987 L209,1017 L197,1046 L191,996 L191,977 L191,957 Z",
            "M430,890 L442,902 L450,915 L450,939 L449,967 L445,1020 L445,1047 L435,1023 L426,999 L419,974 L421,948 L425,922 Z",
        ]
        static let backTraps = [
            "M241,228 L269,213 L286,202 L296,189 L306,175 L311,166 L325,166 L332,175 L342,185 L349,197 L363,209 L382,219 L397,230 L394,240 L380,254 L373,269 L365,288 L358,309 L347,321 L330,338 L311,341 L282,315 L265,262 L251,249 Z",
        ]
        static let backRearDelts = [
            "M418,233 L407,245 L382,261 L395,264 L406,269 L416,279 L423,288 L431,302 L440,302 L452,303 L466,307 L476,317 L474,295 L469,271 L464,255 L449,243 L437,237 Z",
            "M219,233 L238,249 L255,261 L239,266 L227,274 L215,288 L209,303 L198,302 L186,303 L174,307 L164,314 L162,302 L164,285 L169,267 L178,252 L193,240 Z",
        ]
        static let backTriceps = [
            "M431,302 L442,302 L457,307 L476,315 L485,333 L495,353 L497,370 L498,387 L497,401 L483,394 L471,387 L459,391 L445,382 L435,374 L428,357 L426,341 L430,322 Z",
            "M207,302 L209,315 L212,334 L212,348 L205,369 L186,389 L167,387 L142,399 L140,384 L147,353 L152,334 L162,319 L176,309 L188,303 Z",
        ]
        static let backForearms = [
            "M471,435 L473,451 L478,471 L486,485 L495,497 L505,509 L514,523 L524,542 L534,547 L527,523 L517,492 L512,478 L498,458 Z",
            "M498,406 L509,408 L521,422 L529,439 L536,461 L539,480 L545,504 L551,547 L538,528 L517,487 L507,461 L500,434 Z",
            "M164,439 L164,461 L157,482 L145,499 L130,514 L114,545 L102,547 L107,530 L118,506 L126,482 L142,459 Z",
            "M85,550 L95,502 L101,470 L106,447 L119,420 L130,410 L138,405 L142,422 L137,444 L130,466 L126,480 L114,504 L104,521 Z",
        ]
        static let backLowerBack = [
            "M341,487 L359,483 L370,483 L382,485 L394,489 L409,494 L407,477 L407,466 L404,453 L389,451 L371,446 L356,444 L347,444 L347,456 L344,468 Z",
            "M296,487 L282,483 L262,483 L248,489 L229,495 L231,485 L233,473 L234,463 L245,458 L258,458 L270,456 L284,453 L291,447 L293,463 L294,471 Z",
        ]
        static let backLats = [
            "M341,405 L342,374 L346,345 L366,317 L373,295 L380,262 L397,266 L416,281 L435,302 L426,319 L426,338 L428,360 L423,381 L416,398 L409,417 L402,437 L404,453 L390,453 L371,446 L346,444 L346,423 Z",
            "M291,444 L281,454 L262,456 L246,456 L233,461 L234,447 L234,432 L229,415 L222,401 L217,382 L212,362 L214,341 L210,322 L205,305 L217,290 L233,273 L246,264 L258,262 L267,297 L272,315 L281,329 L291,341 L296,357 L299,389 L301,406 L294,422 Z",
        ]
        static let backGlutes = [
            "M413,651 L418,605 L413,566 L409,537 L397,507 L368,490 L349,492 L337,502 L327,521 L322,542 L320,564 L322,586 L325,605 L332,621 L361,627 L385,638 Z",
            "M298,621 L311,607 L318,581 L320,552 L315,530 L310,509 L298,497 L279,492 L262,494 L246,502 L238,518 L231,537 L224,559 L222,585 L222,605 L224,626 L224,648 L243,641 L267,631 L282,627 Z",
        ]
        static let backHamstrings = [
            "M334,617 L354,629 L383,636 L411,648 L425,663 L437,687 L442,710 L442,754 L431,789 L414,802 L389,778 L377,782 L358,751 L346,723 L337,687 L334,658 Z",
            "M308,612 L301,621 L274,631 L246,638 L226,648 L210,667 L202,687 L195,717 L198,751 L209,789 L221,801 L243,785 L255,780 L262,782 L275,759 L293,722 L301,682 L306,653 Z",
        ]
        static let backCalves = [
            "M375,840 L380,814 L389,818 L394,831 L401,854 L406,883 L407,907 L407,929 L404,948 L397,967 L392,977 L382,953 L382,926 L382,890 L380,869 Z",
            "M246,979 L255,950 L257,917 L258,890 L258,869 L265,842 L262,818 L255,813 L246,826 L241,842 L236,861 L231,891 L231,912 L231,931 L236,951 Z",
            "M431,837 L404,807 L404,833 L407,859 L416,893 L419,917 L425,938 L435,957 L445,972 L454,951 L454,924 L447,891 L438,869 Z",
            "M193,972 L186,953 L186,922 L195,888 L202,862 L207,837 L219,821 L234,804 L236,814 L238,835 L229,862 L226,883 L221,915 L214,939 L207,951 Z",
            "M215,954 L230,975 L223,1007 L215,1057 L215,1098 L206,1100 L199,1105 L201,1081 L206,1043 L204,1023 L203,997 L204,978 Z",
            "M441,1105 L429,1096 L424,1067 L417,1011 L407,969 L422,956 L434,971 L437,999 L436,1047 L437,1074 Z",
        ]
    }
}
