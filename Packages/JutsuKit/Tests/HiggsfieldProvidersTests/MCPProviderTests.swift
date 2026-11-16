import Foundation
import HiggsfieldCore
import HiggsfieldMCP
import HiggsfieldTestSupport
import JutsuCore
import JutsuTestSupport
import Testing

@testable import HiggsfieldProviders

extension Network {
    /// Tools and answers as the live server gave them on 2026-10-14, trimmed to the keys the provider reads.
    @Suite struct Provider {
        static let generate = tool("generate_video", "Generate one direct video request", ["params", "context"])
        static let upload = tool("media_upload", "Upload media for use in generation", ["filename", "content_type"])
        static let confirm = tool("media_confirm", "Confirm file uploads", ["media_id", "type"])
        static let status = tool("job_status", "Check the status and results of an async job", ["jobId", "sync"])
        static let balance = tool("balance", "Get the user's available credits and current plan", [])
        static let unrelated = tool("generate_image", "Text to image with motion blur", ["params"])
        static let fullSet = [unrelated, generate, upload, confirm, status, balance]

        static func provider(
            tools: [JSONValue], call: @escaping @Sendable (String, JSONValue) -> JSONValue = { _, _ in [:] }
        )
            -> (HiggsfieldMCPProvider, StubServer)
        {
            let stub = mcpServer(tools: tools, call: call)
            let session = stub.session()
            return (makeProvider(session), stub)
        }

        static func spec(_ mode: Mode) -> JobSpec {
            let source = SourceClip(
                fileURL: URL(fileURLWithPath: "/tmp/in.mov"), duration: 10,
                pixelSize: PixelSize(width: 1280, height: 720),
                range: 0...10)
            return JobSpec(mode: mode, source: source, resolution: .p720)
        }

        static let inputs = RemoteInputs(
            video: RemoteAsset(url: URL(fileURLWithPath: "/in.mp4"), id: "video-1"),
            images: [RemoteAsset(url: URL(fileURLWithPath: "/a.jpg"), id: "image-1")])
        static let image = LocalImage(fileURL: URL(fileURLWithPath: "/tmp/a.jpg"))

        static func calls(_ stub: StubServer) -> [JSONValue] {
            stub.requests.filter { $0.json?["method"] == "tools/call" }.compactMap { $0.json?["params"] }
        }

        /// Where the calls the stub got break their tool's `inputSchema` in the catalog snapshot; empty when none do.
        static func schemaViolations(_ stub: StubServer) throws -> [String] {
            try calls(stub).flatMap { call in
                try CatalogSnapshot.violations(of: call["arguments"] ?? [:], sentTo: call["name"]?.stringValue ?? "")
            }
        }

        @Test func submitSendsTheModelAndMediaIDsAndReadsTheJob() async throws {
            let (provider, stub) = Self.provider(tools: Self.fullSet) { name, _ in
                switch name {
                case "generate_video":
                    ["results": [["id": "job-1", "status": "queued"]], "request_id": "trace-1"]
                case "job_status":
                    [
                        "generation": [
                            "id": "job-1", "status": "completed", "results": ["rawUrl": "https://cdn.example/out.mp4"],
                        ]
                    ]
                case "balance": ["credits": .number(2596.34), "subscription_plan_type": "ultra"]
                default: [:]
                }
            }
            var spec = Self.spec(.motionTransfer)
            spec.prompt = "keep the background"
            let job = try await provider.submit(spec, inputs: Self.inputs, idempotencyKey: UUID())
            #expect(job.requestID == "job-1")
            #expect(job.correlationID == "trace-1")
            let output = try #require(URL(string: "https://cdn.example/out.mp4"))
            #expect(try await provider.status(job) == .completed(videoURL: output))
            #expect(try await provider.balance() == .credits(2596, plan: "ultra"))  // 2596.34, rounded down

            let calls = Self.calls(stub)
            #expect(calls.map { $0["name"] } == ["generate_video", "job_status", "balance"])
            #expect(
                calls.first?["arguments"] == [
                    "params": [
                        "model": "hf_mult_motion_control",
                        "medias": [
                            ["role": "video_references", "value": "video-1"],
                            ["role": "image_references", "value": "image-1"],
                        ],
                        "resolution": "720p", "use_unlim": false, "prompt": "keep the background",
                    ]
                ])
            #expect(calls[1]["arguments"] == ["jobId": "job-1"])
        }

        /// Explicit quotes also protect rounding and duration clamping.
        @Test(arguments: [
            (VideoModel.genjutsu, Resolution.p1080, 10.0, 200), (.seedance25, .p480, 5.5, 18),
            (.seedance25, .p480, 41, 90), (.klingMotionControl, .p1080, 5.5, 18),
        ])
        func estimateFollowsTheModel(
            model: VideoModel, resolution: Resolution, seconds: Double, credits: Int
        ) async throws {
            let (provider, _) = Self.provider(tools: Self.fullSet)
            var spec = Self.spec(.motionTransfer)
            spec.model = model
            spec.resolution = resolution
            spec.source?.range = 0...seconds
            #expect(try await provider.estimate(spec) == .credits(Decimal(credits), isEstimate: true))
        }

        @Test func declinedSubmitCarriesTheServerReason() async throws {
            let (provider, _) = Self.provider(tools: Self.fullSet) { _, _ in ["error": "Not enough credits"] }
            await #expect(throws: ProviderError.validation(field: nil, message: "Not enough credits")) {
                try await provider.submit(Self.spec(.motionTransfer), inputs: Self.inputs, idempotencyKey: UUID())
            }
        }

        @Test(arguments: [
            (JSONValue.object(["status": "queued"]), RemoteStatus.queued),
            (.object(["status": "in_progress"]), .inProgress),
            (.object(["status": "failed", "error": "Bad input"]), .failed(message: "Bad input")),
            (.object(["status": "nsfw"]), .rejected(.explicitContent)),
            (.object(["status": "ip_detected"]), .rejected(.protectedContent)),
            (.object(["status": "canceled"]), .canceled),
        ])
        func statusMapsToRemoteStatus(generation: JSONValue, expected: RemoteStatus) async throws {
            let (provider, _) = Self.provider(tools: Self.fullSet) { _, _ in ["generation": generation] }
            #expect(try await provider.status(RemoteJob(requestID: "job-1")) == expected)
        }

        /// The MCP stub, except that every `generate_video` call answers `status`.
        static func failingSubmit(status: Int) -> (HiggsfieldMCPProvider, StubServer) {
            let mcp = mcpServer(tools: fullSet)
            let stub = StubServer { request, _ in
                request.json?["params"]?["name"] == "generate_video"
                    ? StubResponse(status: status) : mcp.respond(to: request)
            }
            let session = stub.session()
            return (makeProvider(session), stub)
        }

        @Test func ambiguousSubmitFailureIsNotRetryable() async throws {
            let (provider, stub) = Self.failingSubmit(status: 502)
            await #expect(throws: ProviderError.outcomeUnknown) {
                try await provider.submit(Self.spec(.motionTransfer), inputs: Self.inputs, idempotencyKey: UUID())
            }
            #expect(Self.calls(stub).count == 1)
            #expect(try await !provider.submitIsIdempotent(Self.spec(.motionTransfer)))
        }

        @Test(arguments: [
            (-32603 as Int?, ProviderError.outcomeUnknown), (-32000, .outcomeUnknown), (nil, .outcomeUnknown),
            (-32602, .validation(field: nil, message: "Internal failure")),
        ])
        func toolFailuresPreserveWhetherASubmitCanBeRetried(code: Int?, expected: ProviderError) async throws {
            let answering = mcpServer(tools: Self.fullSet)
            let stub = StubServer { request, _ in
                guard request.json?["params"]?["name"] == "generate_video", let id = request.json?["id"] else {
                    return answering.respond(to: request)
                }
                let payload: JSONValue =
                    code.map {
                        ["error": ["code": .number(Double($0)), "message": "Internal failure"]]
                    } ?? ["result": ["isError": true, "content": [["type": "text", "text": "Internal failure"]]]]
                return .json(
                    .object((payload.objectValue ?? [:]).merging(["jsonrpc": "2.0", "id": id]) { _, new in new }))
            }
            let provider = makeProvider(stub.session())
            await #expect(throws: expected) {
                try await provider.submit(Self.spec(.motionTransfer), inputs: Self.inputs, idempotencyKey: UUID())
            }
            #expect(Self.calls(stub).count == 1)
        }

        /// Higgsfield's refusal before execution, as the live server words it, keeps its reason.
        @Test func anInvalidRequestRefusalIsAValidationError() async throws {
            let message = "Invalid request: unknown model \"x\"."
            let answering = mcpServer(tools: Self.fullSet)
            let stub = StubServer { request, _ in
                guard request.json?["params"]?["name"] == "generate_video", let id = request.json?["id"] else {
                    return answering.respond(to: request)
                }
                return .json([
                    "jsonrpc": "2.0", "id": id,
                    "result": ["isError": true, "content": [["type": "text", "text": .string(message)]]],
                ])
            }
            let provider = makeProvider(stub.session())
            await #expect(throws: ProviderError.validation(field: nil, message: message)) {
                try await provider.submit(Self.spec(.motionTransfer), inputs: Self.inputs, idempotencyKey: UUID())
            }
        }

        /// The MCP stub, except that every call to `name` answers with `payload` merged into the JSON-RPC reply.
        static func answering(
            _ name: String, with payload: JSONValue, tools: [JSONValue] = fullSet,
            call: @escaping @Sendable (String, JSONValue) -> JSONValue = { _, _ in [:] }
        ) -> StubServer {
            let answering = mcpServer(tools: tools, call: call)
            return StubServer { request, _ in
                guard request.json?["params"]?["name"]?.stringValue == name, let id = request.json?["id"] else {
                    return answering.respond(to: request)
                }
                return .json(
                    .object((payload.objectValue ?? [:]).merging(["jsonrpc": "2.0", "id": id]) { _, new in new }))
            }
        }

        /// A poll of a job that may already be paid is retried when its answer can't be read, never ended.
        @Test(arguments: [
            JSONValue.object(["result": ["isError": true, "content": [["type": "text", "text": "Busy"]]]]),
            ["error": ["code": -32602, "message": "Invalid params"]],
            ["result": ["content": [["type": "text", "text": "done"]], "structuredContent": [:]]],
        ])
        func anUnreadableStatusIsARetryableServerError(payload: JSONValue) async throws {
            let provider = makeProvider(Self.answering("job_status", with: payload).session())
            await #expect(throws: ProviderError.server(status: 200)) {
                try await provider.status(RemoteJob(requestID: "job-1"))
            }
        }

        /// A paid call that fails before it is sent can be retried: nothing reached the server.
        @Test func aSubmitThatFailsBeforeSendingIsNotSent() async throws {
            let stub = StubServer { request, _ in
                request.json?["method"] == "initialize" ? StubResponse(status: 503) : .notFound
            }
            let provider = makeProvider(stub.session())
            await #expect(throws: ProviderError.notSent) {
                try await provider.submit(Self.spec(.motionTransfer), inputs: Self.inputs, idempotencyKey: UUID())
            }
            let images = ImageRequest(model: "soul_2", prompt: "a knight", aspectRatio: "1:1", count: 1)
            await #expect(throws: ProviderError.notSent) {
                try await provider.submitImages(images, idempotencyKey: UUID())
            }
            #expect(Self.calls(stub).isEmpty)
        }

        @Test(arguments: [(-1.0, 1), (1e30, 1), (Double(Int.max) / 2, 4)])
        func malformedServerPricesAreErrors(credits: Double, variants: Int) async throws {
            let (provider, _) = Self.provider(tools: Self.fullSet) { _, _ in
                ["cost": ["credits_exact": .number(credits)]]
            }
            var spec = Self.spec(.motionTransfer)
            spec.variants = variants
            await #expect(throws: ProviderError.server(status: 200)) {
                try await provider.serverEstimate(spec, inputs: Self.inputs)
            }
        }

        @Test func submitCancelledBeforeTheCallSendsNothing() async throws {
            let (provider, stub) = Self.provider(tools: Self.fullSet)
            let submit = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return try await provider.submit(
                    Self.spec(.motionTransfer), inputs: Self.inputs, idempotencyKey: UUID())
            }
            await #expect(throws: CancellationError.self) { try await submit.value }
            #expect(stub.requests.isEmpty)
        }

        // Darwin only: the stub blocks the loading thread, and Linux Foundation may not end a cancelled task
        // until the load returns.
        #if !canImport(FoundationNetworking)
            @Test func submitCancelledDuringTheCallHasAnUnknownOutcome() async throws {
                let release = DispatchSemaphore(value: 0)
                let (provider, stub) = Self.provider(tools: Self.fullSet) { name, _ in
                    if name == "generate_video" { _ = release.wait(timeout: .now() + 10) }
                    return ["results": [["id": "job-1"]]]
                }
                defer { release.signal() }
                let submit = Task {
                    try await provider.submit(Self.spec(.motionTransfer), inputs: Self.inputs, idempotencyKey: UUID())
                }
                await eventually { Self.calls(stub).count == 1 }

                submit.cancel()
                await #expect(throws: ProviderError.outcomeUnknown) { try await submit.value }
            }
        #endif

        @Test(arguments: [
            (HiggsfieldError.network, true), (.server(status: 500), true), (.server(status: 200), true),
            (.server(status: 404), false), (.unauthorized, false), (.validation(field: nil, message: "x"), false),
        ])
        func ambiguousFailures(error: HiggsfieldError, mayHaveReachedServer: Bool) {
            #expect(HiggsfieldMCPProvider.mayHaveReachedServer(error) == mayHaveReachedServer)
        }
    }
}
