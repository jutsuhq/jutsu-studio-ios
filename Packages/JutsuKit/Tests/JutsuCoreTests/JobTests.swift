import Foundation
import Testing

@testable import JutsuCore

@Test func priceIsTheServerQuoteOnceThereIsOne() throws {
    var job = Job(spec: makeSpec(), providerKind: .apiKey, cost: .usd(3, isEstimate: false))
    #expect(job.price == .usd(3, isEstimate: false))
    job.serverPrice = .usd(2.5, isEstimate: false)
    #expect(job.price == .usd(2.5, isEstimate: false))
    #expect(try JSONDecoder().decode(Job.self, from: JSONEncoder().encode(job)) == job)
}

@Test func onlyAFinishedRemoteGenerationHasAPaidOutput() {
    var job = Job(spec: makeSpec(), providerKind: .apiKey, cost: .usd(1, isEstimate: false))
    job.remote = RemoteJob(requestID: "r1")
    #expect(!job.hasPaidOutput)
    job.chargedAt = Date(timeIntervalSince1970: 1_000)
    #expect(job.hasPaidOutput)
    job.remote = nil
    #expect(!job.hasPaidOutput)
}

@Test func onlyAJobFailedAtTheDeadlineMayStillFinish() {
    var job = Job(spec: makeSpec(), providerKind: .apiKey, cost: .usd(1, isEstimate: false))
    job.remote = RemoteJob(requestID: "r1")
    job.state = .failed(reason: .deadline)
    #expect(job.mayStillFinish)
    job.state = .failed(reason: .generationFailed)
    #expect(!job.mayStillFinish)
    job.state = .failed(reason: .message("Higgsfield didn't finish this job in time."))
    #expect(!job.mayStillFinish)
}
