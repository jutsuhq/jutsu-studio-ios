import Foundation
import JutsuCore
import Testing

@testable import Presentation

extension Locale {
    /// Tests that check dollar amounts pin `CostText.locale` to this, so they don't depend on the Mac's region.
    static let enUS = Locale(identifier: "en_US")
}
