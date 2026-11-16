import Foundation
import Testing

@testable import JobEngine
@testable import JutsuCore

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Serves `RangeStub.body` and honors `Range`. Query options: `status=<code>` answers every request
/// with that status, `ignoreRange=1` always sends the whole body, `dropAt=<offset>` drops the
/// connection the first time a range starts there, `noTotal=1` answers 206 with an unknown total (`/*`),
/// `empty=1` answers 206 without a body. Each test uses its own path, so the process-static
/// logs below never mix tests up; entries stay bounded at a handful per test, which is why the logs
/// are never reset (resetting shared state would race parallel tests instead).
final class RangeStub: URLProtocol {
    static let body = Data("video-bytes".utf8)
    /// "<path> <Range header>" of every request.
    static let requests = CallLog()
    private static let dropped = CallLog()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func option(_ name: String) -> String? { query.first { $0.name == name }?.value }
        let range = request.value(forHTTPHeaderField: "Range")
        Self.requests.append("\(url.path) \(range ?? "-")")

        if let status = option("status").flatMap(Int.init) { return respond(status, [:], Data()) }
        guard option("ignoreRange") == nil, let bounds = range.flatMap(Self.bounds) else {
            return respond(200, ["Content-Length": "\(Self.body.count)"], Self.body)
        }
        if let drop = option("dropAt").flatMap(Int.init), drop == bounds.lowerBound {
            let key = "\(url.path) \(drop)"
            if Self.dropped.count(key) == 0 {
                Self.dropped.append(key)
                client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
                return
            }
        }
        let count = Self.body.count
        if option("empty") != nil {
            return respond(206, ["Content-Range": "bytes \(bounds.lowerBound)-\(bounds.upperBound)/\(count)"], Data())
        }
        guard bounds.lowerBound < count else {
            return respond(416, ["Content-Range": "bytes */\(count)"], Data())
        }
        let end = min(bounds.upperBound, count - 1)
        let total = option("noTotal") == nil ? "\(count)" : "*"
        respond(
            206, ["Content-Range": "bytes \(bounds.lowerBound)-\(end)/\(total)"],
            Data(Self.body[bounds.lowerBound...end]))
    }

    override func stopLoading() {}

    private func respond(_ status: Int, _ headers: [String: String], _ data: Data) {
        guard let url = request.url,
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    /// "bytes=4-7" → 4...7
    private static func bounds(_ header: String) -> ClosedRange<Int>? {
        guard header.hasPrefix("bytes=") else { return nil }
        let parts = header.dropFirst("bytes=".count).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2, parts[0] <= parts[1] else { return nil }
        return parts[0]...parts[1]
    }
}

struct URLSessionDownloaderTests {
    let path = "/\(UUID().uuidString).mp4"
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).partial")
    let downloader = Self.downloader()

    static func downloader(maxBytes: Int64 = 1 << 20, freeSpace: Int64? = nil) -> URLSessionDownloader {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RangeStub.self]
        return URLSessionDownloader(
            session: URLSession(configuration: configuration), chunkSize: 4, maxBytes: maxBytes,
            freeSpace: { _ in freeSpace })
    }

    func url(_ query: String = "") throws -> URL {
        try #require(URL(string: "https://cdn.example\(path)\(query)"))
    }

    var ranges: [String] {
        RangeStub.requests.all.filter { $0.hasPrefix(path + " ") }.map { String($0.dropFirst(path.count + 1)) }
    }

    @Test func resumesFromThePartialFile() async throws {
        try Data("video".utf8).write(to: file)

        try await downloader.download(url(), to: file)

        #expect(try Data(contentsOf: file) == RangeStub.body)
        #expect(ranges == ["bytes=5-8", "bytes=9-12"])
    }

    @Test func aServerIgnoringRangeReplacesThePartialFile() async throws {
        try Data("junk".utf8).write(to: file)

        try await downloader.download(url("?ignoreRange=1"), to: file)

        #expect(try Data(contentsOf: file) == RangeStub.body)
    }
}
