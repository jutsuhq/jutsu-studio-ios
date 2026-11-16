import Foundation
import HiggsfieldCore
import HiggsfieldTestSupport
import Testing

@testable import HiggsfieldMCP

/// `jobs_wait` answers in the shape of the tool's `outputSchema` (catalog snapshot of 2026-10-15; no answer seen yet),
/// and in the other shapes read tolerantly.
enum JobsWaitFixture {
    static let answer: JSONValue = [
        "jobs": [
            [
                "index": 0, "job_id": "job-1", "status": "completed", "type": "video", "model": "seedance_2_5",
                "result_url": "https://cdn.example/1.mp4", "thumbnail_url": "https://cdn.example/1.jpg",
            ],
            ["index": 1, "job_id": "job-2", "status": "in_progress"],
            ["index": 2, "job_id": "job-3", "status": "failed", "error": "Bad input"],
        ],
        "summary": ["total": 3, "completed": 1, "failed": 1, "active": 1, "errors": 0],
        "all_terminal": false, "poll_after_seconds": 5, "timed_out": true,
    ]
}

@Suite struct JobsWaitDecoding {
    static let asked: Set<String> = ["job-1", "job-2", "job-3"]

    @Test func theSchemasShapeIsRead() throws {
        let wait = JobsWait(answer: JobsWaitFixture.answer, asked: Self.asked)
        let output = try #require(URL(string: "https://cdn.example/1.mp4"))
        #expect(
            wait.statuses == [
                "job-1": .completed(videoURL: output), "job-2": .inProgress, "job-3": .failed(message: "Bad input"),
            ])
        #expect(wait.pollAfterSeconds == 5)
    }

    /// The server couldn't look these up, for now or for good: `job_status` is asked instead.
    @Test func failedLookupsAreLeftOut() {
        let answer: JSONValue = [
            "jobs": [
                ["index": 0, "job_id": "job-1", "status": "lookup_failed", "retryable": true],
                ["index": 1, "job_id": "job-2", "status": "lookup_failed", "retryable": false, "error": "Not found"],
                ["index": 2, "job_id": "job-3", "status": "queued"],
            ],
            "all_terminal": false,
        ]
        #expect(JobsWait(answer: answer, asked: Self.asked).statuses == ["job-3": .queued])
    }
}
