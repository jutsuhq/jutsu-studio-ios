import Foundation
import JutsuCore
import Testing

@testable import Presentation

@Suite struct UserMessageTests {
    /// A full disk, also wrapped in another error, asks to free up space instead of showing the system's text.
    @Test func aFullDiskAsksToFreeUpSpace() {
        let full = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: 1, userInfo: [NSUnderlyingErrorKey: full])
        #expect(UserMessage(wrapped) == .notEnoughStorage)
    }

    /// A link error becomes its own alert instead of asking this initializer again until the stack overflows; a full
    /// disk during a download is still the free-up-space one.
    @Test func aLinkErrorSaysWhyItFailed() throws {
        let notMedia = try #require(UserMessage(MediaLinkError.notMedia(contentType: "text/html")))
        #expect(notMedia.message.contains(".mp4"))
        let refused = try #require(UserMessage(MediaLinkError.unavailable(status: 404)))
        #expect(refused.message.contains("404"))
        #expect(UserMessage(MediaLinkError.notEnoughSpace) == .notEnoughStorage)
    }

    /// An unreadable 2xx answer doesn't tell the person the server "answered 200".
    @Test func anUnreadableAnswerNamesNoStatus() throws {
        let message = try #require(UserMessage(ProviderError.server(status: 200), kind: .account))
        #expect(!message.message.contains("200"))
    }

    /// A refused sign-in leads to the account settings.
    @Test func anExpiredSignInOpensSettings() {
        #expect(UserMessage(ProviderError.unauthorized, kind: .account)?.action == .openSettings)
    }
}
