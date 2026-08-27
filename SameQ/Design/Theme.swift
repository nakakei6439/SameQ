import SwiftUI

/// 色と共通パーツ。
/// 参考モックアップに合わせて、淡い水彩調の背景・白い角丸カード・緑のプライマリボタン。
/// 装飾は控えめにして、カードと文字が主役になる濃度に寄せる。
enum Theme {
    static let background = Color(red: 0.957, green: 0.973, blue: 0.949)
    static let backgroundTop = Color(red: 0.918, green: 0.957, blue: 0.973)
    static let surface = Color.white
    static let ink = Color(red: 0.129, green: 0.145, blue: 0.129)
    static let inkSecondary = Color(red: 0.404, green: 0.435, blue: 0.404)
    static let inkTertiary = Color(red: 0.604, green: 0.635, blue: 0.608)
    static let accent = Color(red: 0.310, green: 0.647, blue: 0.443)
    static let like = Color(red: 0.898, green: 0.400, blue: 0.451)
    static let hairline = Color(red: 0.867, green: 0.898, blue: 0.867)

    static let cardCornerRadius: CGFloat = 24

    /// 画面全体の背景。空から草原へ、という程度の弱いグラデーション。
    static var canvas: some View {
        LinearGradient(
            colors: [backgroundTop, background],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    /// 世界タイムラインの上部に出るお題表示帯の背景（F39 / スプリント16）。
    /// 白サーフェスに hairline の細い枠線を組み合わせ、淡いキャンバス背景とのあいだで
    /// `Theme.ink`（≈ #212521）のお題本文が WCAG AA の 4.5:1 を大きく超えるコントラスト
    /// で読める。白（#FFFFFF）に対する ink のコントラスト比は約 14:1（十分）。
    static let promptStripSurface: Color = surface
    static let promptStripBorder: Color = hairline

}

/// 白い角丸カード。淡い影だけ落として、輪郭線は引かない。
struct CardBackground: ViewModifier {
    var cornerRadius: CGFloat = Theme.cardCornerRadius

    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.surface)
                .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 4)
        )
    }
}

extension View {
    func cardBackground(cornerRadius: CGFloat = Theme.cardCornerRadius) -> some View {
        modifier(CardBackground(cornerRadius: cornerRadius))
    }
}

/// 画面下の主ボタン。
///
/// 押せない状態は色でも分かるようにする。`@Environment(\.isEnabled)` は
/// ButtonStyle の中では期待通りに解決されなかったので、呼び出し側から渡す。
struct PrimaryButtonStyle: ButtonStyle {
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(enabled ? Theme.accent : Color(white: 0.55))
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// 補助的な文字ボタン。
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Theme.inkSecondary)
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}
