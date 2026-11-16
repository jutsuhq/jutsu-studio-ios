import Foundation
import HiggsfieldCore
import HiggsfieldTestSupport
import Testing

@testable import HiggsfieldMCP

extension Network {
    /// The tool contract as the live server gave it on 2026-10-14, trimmed to the keys the client reads.
    @Suite struct Account {
        static let fullSet = [
            tool("generate_image", "Text to image", ["params"]),
            tool("generate_video", "Generate one direct video request", ["params", "context"]),
            tool("media_upload", "Upload media for use in generation", ["filename", "content_type"]),
            tool("media_confirm", "Confirm file uploads", ["media_id", "type"]),
            tool("job_status", "Check the status and results of an async job", ["jobId", "sync"]),
            tool("balance", "Get the user's available credits and current plan", []),
        ]

        static let request = VideoRequest(
            model: .klingMotionControl,
            media: [.init(role: .video, id: "video-1"), .init(role: .image, id: "image-1")], prompt: "slow",
            mode: VideoRequest.klingPro, duration: 10)

        static func account(
            tools: [JSONValue] = fullSet, call: @escaping @Sendable (String, JSONValue) -> JSONValue = { _, _ in [:] }
        ) -> (HiggsfieldAccount, StubServer) {
            account(tools: Locked(tools), call: call)
        }

        /// A server whose tool list the test changes through `tools`.
        static func account(
            tools: Locked<[JSONValue]>,
            call: @escaping @Sendable (String, JSONValue) -> JSONValue = { _, _ in [:] }
        ) -> (HiggsfieldAccount, StubServer) {
            let stub = mcpServer(tools: { tools.value }, call: call)
            let session = stub.session()
            let client = MCPClient(endpoint: Fixture.mcpURL, tokens: tokenProvider(), session: session)
            return (HiggsfieldAccount(client: client, session: session), stub)
        }

        static func calls(_ stub: StubServer) -> [JSONValue] {
            stub.requests.filter { $0.json?["method"] == "tools/call" }.compactMap { $0.json?["params"] }
        }

        @Test func generateSendsTheParamsAndReadsTheJob() async throws {
            let (account, stub) = Self.account { _, _ in ["results": [["id": "job-1"]], "request_id": "trace-1"] }

            #expect(try await account.refreshTools())
            let generation = try await account.generate(Self.request)

            #expect(generation == Generation(id: "job-1", requestID: "trace-1"))
            #expect(
                Self.calls(stub).first
                    == [
                        "name": "generate_video",
                        "arguments": [
                            "params": [
                                "model": "kling3_0_motion_control",
                                "medias": [
                                    ["role": "video_references", "value": "video-1"],
                                    ["role": "image_references", "value": "image-1"],
                                ],
                                "mode": "pro", "duration": 10, "prompt": "slow", "use_unlim": false,
                            ]
                        ],
                    ])
        }

        @Test func anUnreadableGenerateReplyIsNotARefusal() async throws {
            let (unreadable, _) = Self.account { _, _ in ["results": []] }
            await #expect(throws: HiggsfieldError.server(status: 200)) { try await unreadable.generate(Self.request) }

            let (declined, _) = Self.account { _, _ in ["error": "Prompt is too long"] }
            await #expect(throws: HiggsfieldError.validation(field: nil, message: "Prompt is too long")) {
                try await declined.generate(Self.request)
            }
        }

        /// The output schema's out-of-credits recovery names no job: nothing was submitted.
        @Test func aBillingRecoveryIsInsufficientFunds() async throws {
            let (account, _) = Self.account { _, _ in
                ["recovery_tool": "show_plans_and_credits", "recovery_tool_args": ["intent": "topup"]]
            }
            await #expect(throws: HiggsfieldError.insufficientFunds) { try await account.generate(Self.request) }

            let (asking, _) = Self.account { _, _ in
                ["unlim_choice": ["message": "Use free generations?", "model": "m"]]
            }
            await #expect(throws: HiggsfieldError.validation(field: nil, message: "Use free generations?")) {
                try await asking.generate(Self.request)
            }
        }

        /// As the server answered a long Genjutsu prompt on 2026-10-14, trimmed.
        static let presetNotice: JSONValue = [
            "notice": [
                "type": "preset_recommendation",
                "message": "This prompt looks like the Higgsfield preset \"IN THE DARK\".",
                "data": ["retry_literal_with": ["declined_preset_id": "preset-1"]],
            ]
        ]

        @Test func aNoticeDoesNotResubmitAnAcceptedGeneration() async throws {
            let (account, stub) = Self.account { _, _ in
                var answer = Self.presetNotice.objectValue ?? [:]
                answer["results"] = [["id": "paid-job"]]
                return .object(answer)
            }
            #expect(try await account.generate(Self.request).id == "paid-job")
            #expect(Self.calls(stub).count == 1)
        }

        @Test func aNoticeAloneSubmittedNothing() async throws {
            let (account, stub) = Self.account { _, _ in Self.presetNotice }
            await #expect(
                throws: HiggsfieldError.validation(
                    field: nil, message: "This prompt looks like the Higgsfield preset \"IN THE DARK\".")
            ) { try await account.generate(Self.request) }
            #expect(Self.calls(stub).count == 2)
        }

        @Test(arguments: [
            (JSONValue.object(["status": "pending"]), GenerationStatus.queued),
            (.object(["status": "failed", "error": "Bad input"]), .failed(message: "Bad input")),
            (.object(["status": "ip_detected"]), .rejected(.protectedContent)),
            (.object(["status": "nsfw"]), .rejected(.explicitContent)),
            (.object(["status": "cancelled"]), .canceled),
            (
                .object(["status": "completed", "results": ["rawUrl": "https://cdn.example/out.mp4"]]),
                .completed(videoURL: URL(string: "https://cdn.example/out.mp4")!)
            ),
        ])
        func statusReadsTheGeneration(generation: JSONValue, expected: GenerationStatus) async throws {
            let (account, stub) = Self.account { _, _ in ["generation": generation] }
            #expect(try await account.status(of: "job-1") == expected)
            #expect(Self.calls(stub).first?["arguments"] == ["jobId": "job-1"])
        }

        /// Neither a generation nor an error: the job may be paid and running, so it is polled again.
        @Test func anEmptyAnswerIsPolledAgain() async throws {
            let (account, _) = Self.account { _, _ in [:] }
            await #expect(throws: HiggsfieldError.server(status: 200)) { try await account.status(of: "job-1") }
        }

        /// The schema's `retryable` marks a lookup that failed only for now: the job may still be running, so a video
        /// and an image job are both polled again rather than failed.
        @Test func aRetryableErrorIsPolledAgain() async throws {
            let (account, _) = Self.account { _, _ in ["error": "Job lookup timed out", "retryable": true] }
            await #expect(throws: HiggsfieldError.server(status: 200)) { try await account.status(of: "job-1") }
            await #expect(throws: HiggsfieldError.server(status: 200)) { try await account.imageStatus(of: "job-1") }
        }

        @Test func aStatedErrorEndsTheJobWithTheServersReason() async throws {
            let (account, _) = Self.account { _, _ in ["error": "Job not found"] }
            await #expect(throws: HiggsfieldError.validation(field: nil, message: "Job not found")) {
                try await account.status(of: "job-1")
            }
        }
    }
}
