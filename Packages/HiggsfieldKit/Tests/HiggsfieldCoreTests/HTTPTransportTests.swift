import Foundation
import Testing

@testable import HiggsfieldCore

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

private struct DownloadFailed: Error, Equatable {}

@Test func aMissingHTTPResponseThrowsTheCallersNetworkError() throws {
    #expect(throws: HiggsfieldError.network) { try HTTPURLResponse.required(nil) }
    #expect(throws: DownloadFailed()) { try HTTPURLResponse.required(nil, networkError: DownloadFailed()) }
    let url = try #require(URL(string: "https://cdn.example/a.mp4"))
    let response = try #require(HTTPURLResponse(url: url, statusCode: 204, httpVersion: nil, headerFields: nil))
    #expect(try HTTPURLResponse.required(response).isSuccess)
}
