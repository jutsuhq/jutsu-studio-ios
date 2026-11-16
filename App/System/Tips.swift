import SwiftUI
import TipKit

/// What a long press on a take offers; shown once there is a take to press.
struct TakeMenuTip: Tip {
    var title: Text { Text("Long-press a take") }
    var message: Text? { Text("Preview it, star it, reuse it in Create, compare it or drag it to another app.") }
    var image: Image? { Image(systemName: "hand.tap") }
}
