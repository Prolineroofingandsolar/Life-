import SwiftUI

// MARK: - Body Region

private enum BodyRegion: Hashable {
    case chest, shoulders, arms, core, upperLegs, lowerLegs, full

    static func regions(for muscle: String) -> Set<BodyRegion> {
        let m = muscle.lowercased()
        if m.contains("chest") || m.contains("pec") { return [.chest] }
        if m.contains("back") || m.contains("lat") || m.contains("trap") || m.contains("rhomboid") { return [.chest] } // share torso shape
        if m.contains("shoulder") || m.contains("delt") { return [.shoulders] }
        if m.contains("bicep") || m.contains("tricep") || m.contains("arm") || m.contains("forearm") { return [.arms] }
        if m.contains("quad") || m.contains("hamstring") || m.contains("glute") || m.contains("leg") || m.contains("hip") { return [.upperLegs, .lowerLegs] }
        if m.contains("calf") || m.contains("calve") { return [.lowerLegs] }
        if m.contains("core") || m.contains("abs") || m.contains("oblique") { return [.core] }
        if m.contains("cardio") || m.contains("conditioning") { return [.full] }
        return []
    }
}

// MARK: - Body Diagram View

struct BodyDiagramView: View {
    let muscle: String
    var size: CGFloat = 40

    private var highlighted: Set<BodyRegion> { BodyRegion.regions(for: muscle) }

    private func fill(_ region: BodyRegion) -> Color {
        (highlighted.contains(region) || highlighted.contains(.full))
            ? Color(hex: "#30d158")
            : Color.white.opacity(0.13)
    }

    var body: some View {
        Canvas { ctx, sz in
            let w = sz.width
            let h = sz.height

            // Head
            let hR = w * 0.15
            var head = Path()
            head.addEllipse(in: CGRect(x: w/2 - hR, y: 0, width: hR*2, height: hR*2))
            ctx.fill(head, with: .color(Color.white.opacity(0.13)))

            // Shoulders
            let shoulderY = hR * 2 + 1
            let sW = w * 0.18
            let sH = h * 0.08
            var lShoulder = Path()
            lShoulder.addEllipse(in: CGRect(x: w*0.04, y: shoulderY, width: sW, height: sH))
            var rShoulder = Path()
            rShoulder.addEllipse(in: CGRect(x: w*0.78, y: shoulderY, width: sW, height: sH))
            ctx.fill(lShoulder, with: .color(fill(.shoulders)))
            ctx.fill(rShoulder, with: .color(fill(.shoulders)))

            // Chest
            let torsoX = w * 0.28
            let torsoW = w * 0.44
            let chestH = h * 0.16
            let chestRect = CGRect(x: torsoX, y: shoulderY, width: torsoW, height: chestH)
            ctx.fill(Path(roundedRect: chestRect, cornerRadius: 2), with: .color(fill(.chest)))

            // Arms
            let armW = w * 0.1
            let armH = h * 0.22
            let armTop = shoulderY + sH * 0.5
            var lArm = Path()
            lArm.addRoundedRect(in: CGRect(x: w*0.07, y: armTop, width: armW, height: armH), cornerSize: CGSize(width: 3, height: 3))
            var rArm = Path()
            rArm.addRoundedRect(in: CGRect(x: w*0.83, y: armTop, width: armW, height: armH), cornerSize: CGSize(width: 3, height: 3))
            ctx.fill(lArm, with: .color(fill(.arms)))
            ctx.fill(rArm, with: .color(fill(.arms)))

            // Core
            let coreTop = shoulderY + chestH + 1
            let coreH = h * 0.12
            let coreRect = CGRect(x: torsoX, y: coreTop, width: torsoW, height: coreH)
            ctx.fill(Path(roundedRect: coreRect, cornerRadius: 2), with: .color(fill(.core)))

            // Upper legs
            let legW = w * 0.19
            let legGap = w * 0.04
            let legsTop = coreTop + coreH + 2
            let upperH = h * 0.2
            let lUpper = Path(roundedRect: CGRect(x: w/2 - legGap - legW, y: legsTop, width: legW, height: upperH), cornerSize: CGSize(width: 3, height: 3))
            let rUpper = Path(roundedRect: CGRect(x: w/2 + legGap, y: legsTop, width: legW, height: upperH), cornerSize: CGSize(width: 3, height: 3))
            ctx.fill(lUpper, with: .color(fill(.upperLegs)))
            ctx.fill(rUpper, with: .color(fill(.upperLegs)))

            // Lower legs
            let lowerTop = legsTop + upperH + 2
            let lowerH = h * 0.2
            let lLower = Path(roundedRect: CGRect(x: w/2 - legGap - legW, y: lowerTop, width: legW, height: lowerH), cornerSize: CGSize(width: 3, height: 3))
            let rLower = Path(roundedRect: CGRect(x: w/2 + legGap, y: lowerTop, width: legW, height: lowerH), cornerSize: CGSize(width: 3, height: 3))
            ctx.fill(lLower, with: .color(fill(.lowerLegs)))
            ctx.fill(rLower, with: .color(fill(.lowerLegs)))
        }
        .frame(width: size, height: size * 1.55)
    }
}
