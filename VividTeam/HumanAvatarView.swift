// HumanAvatarView.swift
// Stylised flat-design human face illustrations drawn entirely in SwiftUI.
// Each AvatarStyle produces a distinct look: hair shape, skin tone, shirt colour.
// All measurements are proportional to the view's minimum dimension (s)
// so the face scales correctly at any size (dock icon ~50pt → detail panel ~90pt).

import SwiftUI

// MARK: - Avatar style catalogue

enum AvatarStyle: String, CaseIterable {
    case alex   // Dev     – short dark hair, fair skin, glasses
    case maya   // Design  – dark bun, warm golden skin
    case sam    // Research – natural afro, deep brown skin
    case kai    // Data    – straight black bob with fringe, olive skin
    case lee    // Ops     – auburn ponytail, fair skin

    // ── Palette ─────────────────────────────────────────────────────────────

    var skinTone:  Color { avatarPalette.skin  }
    var hairColor: Color { avatarPalette.hair  }
    var shirtColor: Color { avatarPalette.shirt }

    private var avatarPalette: (skin: Color, hair: Color, shirt: Color) {
        switch self {
        case .alex:
            return (
                skin:  Color(red: 1.00, green: 0.87, blue: 0.80),   // fair peachy
                hair:  Color(red: 0.18, green: 0.13, blue: 0.10),   // near-black brown
                shirt: Color(red: 0.15, green: 0.25, blue: 0.55)    // navy
            )
        case .maya:
            return (
                skin:  Color(red: 0.90, green: 0.72, blue: 0.54),   // warm caramel
                hair:  Color(red: 0.22, green: 0.14, blue: 0.07),   // dark espresso
                shirt: Color(red: 0.85, green: 0.38, blue: 0.38)    // coral
            )
        case .sam:
            return (
                skin:  Color(red: 0.45, green: 0.28, blue: 0.16),   // rich warm brown
                hair:  Color(red: 0.12, green: 0.08, blue: 0.06),   // deep black-brown
                shirt: Color(red: 0.13, green: 0.55, blue: 0.55)    // teal
            )
        case .kai:
            return (
                skin:  Color(red: 0.93, green: 0.83, blue: 0.73),   // light olive
                hair:  Color(red: 0.10, green: 0.08, blue: 0.08),   // blue-black
                shirt: Color(red: 0.28, green: 0.50, blue: 0.35)    // sage green
            )
        case .lee:
            return (
                skin:  Color(red: 1.00, green: 0.88, blue: 0.83),   // fair pink
                hair:  Color(red: 0.68, green: 0.25, blue: 0.10),   // auburn red
                shirt: Color(red: 0.42, green: 0.25, blue: 0.65)    // purple
            )
        }
    }
}

// MARK: - Main view

struct HumanAvatarView: View {
    let style: AvatarStyle

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            faceStack(s: s)
                .frame(width: s, height: s)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .clipShape(Circle())
    }

    // MARK: Layered face composition

    @ViewBuilder
    private func faceStack(s: CGFloat) -> some View {
        ZStack {
            // ① Shirt background (fills the whole circle)
            Circle().fill(style.shirtColor)

            // ② Neck (skin, lower-centre strip bridging head → shirt)
            Capsule()
                .fill(style.skinTone)
                .frame(width: s * 0.22, height: s * 0.28)
                .offset(y: s * 0.26)

            // ③ Hair behind head (drawn BEFORE head so head clips bottom of hair)
            hairBehind(s: s)

            // ④ Head
            Circle()
                .fill(style.skinTone)
                .frame(width: s * 0.56, height: s * 0.56)
                .offset(y: -s * 0.06)

            // ⑤ Hair in front of head (fringe, bun, ponytail tip)
            hairFront(s: s)

            // ⑥ Eyes
            eyesView(s: s)
                .offset(y: -s * 0.13)

            // ⑦ Smile
            smileView(s: s)
                .offset(y: -s * 0.01)

            // ⑧ Style extras (glasses for Alex)
            extras(s: s)
        }
    }

    // MARK: Hair layers

    @ViewBuilder
    private func hairBehind(s: CGFloat) -> some View {
        let c = style.hairColor
        switch style {

        case .alex:
            // Short neat side-part — rounded cap sitting on top of head
            Capsule()
                .fill(c)
                .frame(width: s * 0.64, height: s * 0.42)
                .offset(y: -s * 0.26)

        case .maya:
            // Hair mass behind head; bun drawn in hairFront
            ZStack {
                Capsule()
                    .fill(c)
                    .frame(width: s * 0.56, height: s * 0.32)
                    .offset(y: -s * 0.28)
                // Low bun stalk
                Capsule()
                    .fill(c)
                    .frame(width: s * 0.10, height: s * 0.22)
                    .offset(y: -s * 0.42)
            }

        case .sam:
            // Afro — large soft circle around/above head
            Circle()
                .fill(c)
                .frame(width: s * 0.76, height: s * 0.76)
                .offset(y: -s * 0.14)
                .blur(radius: s * 0.025)   // subtle fuzz at the edge

        case .kai:
            // Bob with fringe — covers sides and top; fringe is in hairFront
            RoundedRectangle(cornerRadius: s * 0.14, style: .continuous)
                .fill(c)
                .frame(width: s * 0.64, height: s * 0.50)
                .offset(y: -s * 0.26)

        case .lee:
            // Ponytail base — covers top; tail is in hairFront
            Capsule()
                .fill(c)
                .frame(width: s * 0.60, height: s * 0.36)
                .offset(y: -s * 0.26)
        }
    }

    @ViewBuilder
    private func hairFront(s: CGFloat) -> some View {
        let c = style.hairColor
        switch style {

        case .alex:
            EmptyView()   // clean short look, nothing in front

        case .maya:
            // Bun knot on top of head
            ZStack {
                Circle()
                    .fill(c)
                    .frame(width: s * 0.24, height: s * 0.24)
                    .offset(y: -s * 0.44)
                // Highlight on bun
                Circle()
                    .fill(c.opacity(0.4))
                    .frame(width: s * 0.08)
                    .offset(x: -s * 0.04, y: -s * 0.47)
            }

        case .sam:
            EmptyView()   // afro is all one mass

        case .kai:
            // Straight fringe across forehead
            RoundedRectangle(cornerRadius: s * 0.04, style: .continuous)
                .fill(c)
                .frame(width: s * 0.52, height: s * 0.10)
                .offset(y: -s * 0.16)

        case .lee:
            // Ponytail extending lower-right
            Capsule()
                .fill(c)
                .frame(width: s * 0.14, height: s * 0.36)
                .rotationEffect(.degrees(25))
                .offset(x: s * 0.30, y: -s * 0.08)
        }
    }

    // MARK: Eyes

    private func eyesView(s: CGFloat) -> some View {
        HStack(spacing: s * 0.13) {
            singleEye(s: s)
            singleEye(s: s)
        }
    }

    private func singleEye(s: CGFloat) -> some View {
        ZStack {
            // Sclera
            Ellipse()
                .fill(.white)
                .frame(width: s * 0.10, height: s * 0.09)
            // Iris
            Circle()
                .fill(Color(red: 0.22, green: 0.16, blue: 0.10))
                .frame(width: s * 0.060)
            // Catchlight
            Circle()
                .fill(.white)
                .frame(width: s * 0.022)
                .offset(x: s * 0.016, y: -s * 0.016)
        }
    }

    // MARK: Smile

    private func smileView(s: CGFloat) -> some View {
        Canvas { ctx, size in
            let cx = size.width  / 2
            let cy = size.height / 2
            let r  = size.width  * 0.38

            var path = Path()
            path.addArc(
                center:     CGPoint(x: cx, y: cy),
                radius:     r,
                startAngle: .degrees(20),
                endAngle:   .degrees(160),
                clockwise:  false
            )
            ctx.stroke(
                path,
                with:      .color(.black.opacity(0.35)),
                style:     StrokeStyle(lineWidth: s * 0.028, lineCap: .round)
            )
        }
        .frame(width: s * 0.24, height: s * 0.12)
    }

    // MARK: Extras

    @ViewBuilder
    private func extras(s: CGFloat) -> some View {
        switch style {
        case .alex:
            // Thin rectangular glasses
            HStack(spacing: s * 0.04) {
                RoundedRectangle(cornerRadius: s * 0.02)
                    .stroke(.black.opacity(0.55), lineWidth: s * 0.022)
                    .frame(width: s * 0.14, height: s * 0.08)
                RoundedRectangle(cornerRadius: s * 0.02)
                    .stroke(.black.opacity(0.55), lineWidth: s * 0.022)
                    .frame(width: s * 0.14, height: s * 0.08)
            }
            .offset(y: -s * 0.12)
        default:
            EmptyView()
        }
    }
}
