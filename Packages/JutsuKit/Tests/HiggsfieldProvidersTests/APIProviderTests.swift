import Foundation
import HiggsfieldTestSupport
import JutsuCore
import Testing

@testable import HiggsfieldProviders

private let inputs = RemoteInputs(
    video: RemoteAsset(url: URL(string: "https://cdn.example.com/in.mp4")!),
    images: [RemoteAsset(url: URL(string: "https://cdn.example.com/a.jpg")!)])

private func spec(_ mode: Mode = .motionTransfer, presetID: UUID? = nil) -> JobSpec {
    let source = SourceClip(
        fileURL: URL(fileURLWithPath: "/tmp/source.mov"), duration: 60,
        pixelSize: PixelSize(width: 1280, height: 720), range: 0...12)
    return JobSpec(mode: mode, source: source, presetID: presetID, prompt: "", resolution: .p480)
}

@Test func clientErrorsArriveAsProviderErrors() async {
    let server = StubServer()
    server.on(
        "POST", "/higgsfield/genjutsu/motion-transfer/v1.0",
        StubResponse(status: 429, headers: ["Retry-After": "30"], body: #"{"detail": {"code": "account_queue_full"}}"#))
    server.on("GET", "/requests/req-1/status", fail: URLError(.notConnectedToInternet))
    let provider = server.makeAPIProvider()

    await #expect(throws: ProviderError.concurrencyLimit(retryAfter: 30)) {
        try await provider.submit(spec(), inputs: inputs, idempotencyKey: UUID())
    }
    await #expect(throws: ProviderError.network) { try await provider.status(RemoteJob(requestID: "req-1")) }
}

@Test func serverEstimateIsExactUSD() async throws {
    let server = StubServer()
    server.on(
        "POST", "/estimate/higgsfield/genjutsu/motion-transfer/v1.0",
        StubResponse(body: #"{"credits": "61.000", "usd": "3.816"}"#))

    let price = try await server.makeAPIProvider().serverEstimate(spec(), inputs: inputs)

    #expect(price == .usd(Decimal(string: "3.816") ?? 0, isEstimate: false))
}

@Test func providerBillsInDollarsAtItsListPrice() async throws {
    let provider = StubServer().makeAPIProvider(keyID: "kid-1")

    #expect(try await provider.capabilities().costUnit == .usd)
    #expect(try await provider.estimate(spec()) == .usd(Decimal(string: "3.816") ?? 0, isEstimate: false))
    #expect(try await provider.balance() == nil)
    #expect(try await provider.submitIsIdempotent(spec()))
}

@Test func providerPollsAndCancelsByRequestID() async throws {
    let server = StubServer()
    server.on("GET", "/requests/req-7/status", StubResponse(body: #"{"status": "nsfw", "request_id": "req-7"}"#))
    server.on("POST", "/requests/req-7/cancel", StubResponse(status: 400, body: #"{"detail": "Not queued"}"#))
    let provider = server.makeAPIProvider()
    let job = RemoteJob(requestID: "req-7")

    #expect(try await provider.status(job) == .rejected(.explicitContent))
    await #expect(throws: ProviderError.validation(field: nil, message: "Not queued")) {
        try await provider.cancel(job)
    }
}

/// A Seedance job: from a 1080×1920 source when `hasSource`, else a 9:16 clip of 8 s from the prompt.
private func seedance(hasSource: Bool, references: Int = 0, audio: AudioOption = .original) -> JobSpec {
    let images = (0..<references).map { LocalImage(fileURL: URL(fileURLWithPath: "/tmp/ref\($0).jpg")) }
    let source = SourceClip(
        fileURL: URL(fileURLWithPath: "/tmp/source.mov"), duration: 60,
        pixelSize: PixelSize(width: 1080, height: 1920), range: 0...12)
    return JobSpec(
        mode: .motionTransfer, model: .seedance25, source: hasSource ? source : nil, references: images,
        prompt: "a fox in the snow", resolution: .p720, audio: audio, length: hasSource ? nil : 8,
        aspectRatio: hasSource ? nil : .portrait)
}

/// A job with nothing to upload is quoted by `POST /estimate` with the body its submit sends, before anything else
/// happens; jobs that differ only in the prompt share the quote.
@Test func aJobWithoutMediaIsQuotedBeforeUpload() async throws {
    let server = StubServer()
    server.on(
        "POST", "/estimate/bytedance/seedance-2.5/text-to-video",
        StubResponse(body: #"{"credits": "59.000", "usd": "3.69"}"#))
    let provider = server.makeAPIProvider()
    let quote = Cost.usd(Decimal(string: "3.69") ?? 0, isEstimate: false)
    var reworded = seedance(hasSource: false)
    reworded.prompt = "a fox in the rain"

    #expect(try await provider.estimate(seedance(hasSource: false)) == quote)
    #expect(try await provider.estimate(reworded) == quote)

    #expect(server.requests.map(\.path) == ["/estimate/bytedance/seedance-2.5/text-to-video"])
    #expect(
        server.requests.first?.bodyText
            == #"{"aspect_ratio":"9:16","duration":8,"generate_audio":true,"prompt":"a fox in the snow","resolution":"720p"}"#
    )
}

/// A failed quote leaves the list price, and isn't kept: the next estimate asks again. A job with media, or without
/// the prompt its request needs, isn't quoted before upload.
@Test func withoutAQuoteTheListPriceStands() async throws {
    let server = StubServer()
    server.on("POST", "/estimate/bytedance/seedance-2.5/text-to-video", StubResponse(status: 503, body: "{}"))
    let provider = server.makeAPIProvider()
    let listPrice = Cost.usd(Decimal(string: "3.6976") ?? 0, isEstimate: true)
    var unprompted = seedance(hasSource: false)
    unprompted.prompt = " "

    #expect(try await provider.estimate(seedance(hasSource: false)) == listPrice)
    #expect(try await provider.estimate(seedance(hasSource: false)) == listPrice)
    #expect(try await provider.estimate(unprompted) == listPrice)
    #expect(try await provider.estimate(seedance(hasSource: false, references: 1)) == listPrice)
    #expect(server.requests.count == 2)
}
