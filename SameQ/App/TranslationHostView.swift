import SwiftUI
import Translation

/// `Translator` に `TranslationSession` を供給するためだけの、見えないビュー（F18 / F22）。
///
/// `TranslationSession` は SwiftUI の `.translationTask` 修飾子からしか作れないので、
/// アプリのルートに常駐させておく。画面（今日のお題／タイムライン／設定）がどれだけ
/// 切り替わっても、このビューだけは `RootView` の背景として生き続ける。
struct TranslationHostView: View {
    let translator: Translator

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .translationTask(translator.configuration) { session in
                await translator.resolve(session: session)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
