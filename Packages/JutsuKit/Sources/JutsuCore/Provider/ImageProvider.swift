import Foundation

/// An image model the connection offers for making reference images.
public struct ImageModel: Codable, Sendable, Hashable, Identifiable {
    /// What the input image of an edit may be.
    public enum Input: Codable, Sendable, Hashable {
        /// Text to image only.
        case none
        /// Generates from the prompt alone, or edits an image when one is given.
        case optional
        /// Edits only: an image is required.
        case required
    }

    /// The REST endpoint ID, or the account's model ID.
    public var id: String
    public var title: String
    /// How many images one request can make, ascending; `[1]` when it makes one.
    public var variantCounts: [Int]
    /// The frames the model takes, as "W:H".
    public var aspectRatios: [String]
    public var input: Input
    /// The most input images one request takes, where the model's catalog says; `nil` takes one, unless
    /// `unstatedInputLimit` is set. 0 with `none`.
    public var maxInputs: Int?
    /// For a model that takes images but whose catalog states no most: how many may be sent anyway, `inputBound`.
    /// The provider's own quote then refuses more than the model takes, before anything is sent or paid.
    public var unstatedInputLimit: Int?
    /// The public list price of one image, labelled as an estimate; `nil` when none is known.
    public var listPrice: Cost?
    /// The model's own choices beside the frame and count, such as its resolution: `ImageRequest.settings`.
    public var settings: [Setting]

    /// One of a model's choices, as the catalog lists it: a parameter name, its values and the one it uses unasked.
    public struct Setting: Codable, Sendable, Hashable {
        /// The parameter, "resolution" or "quality".
        public var name: String
        /// Its values, as the catalog spells them: "1k", "2k", "4k"; "low", "high".
        public var options: [String]
        /// One of `options`.
        public var defaultValue: String

        public init(name: String, options: [String], defaultValue: String? = nil) {
            self.name = name
            self.options = options
            self.defaultValue = defaultValue.flatMap { options.contains($0) ? $0 : nil } ?? options.first ?? ""
        }
    }

    public init(
        id: String, title: String, variantCounts: [Int] = [1], aspectRatios: [String], input: Input = .none,
        listPrice: Cost? = nil, maxInputs: Int? = nil, unstatedInputLimit: Int? = nil, settings: [Setting] = []
    ) {
        self.id = id
        self.title = title
        self.variantCounts = variantCounts.isEmpty ? [1] : variantCounts
        self.aspectRatios = aspectRatios
        self.input = input
        self.listPrice = listPrice
        self.maxInputs = maxInputs
        self.unstatedInputLimit = unstatedInputLimit
        self.settings = settings
    }

    /// Models saved before `settings` decode with none.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(String.self, forKey: .id),
            title: try container.decode(String.self, forKey: .title),
            variantCounts: try container.decode([Int].self, forKey: .variantCounts),
            aspectRatios: try container.decode([String].self, forKey: .aspectRatios),
            input: try container.decode(Input.self, forKey: .input),
            listPrice: try container.decodeIfPresent(Cost.self, forKey: .listPrice),
            maxInputs: try container.decodeIfPresent(Int.self, forKey: .maxInputs),
            unstatedInputLimit: try container.decodeIfPresent(Int.self, forKey: .unstatedInputLimit),
            settings: try container.decodeIfPresent([Setting].self, forKey: .settings) ?? [])
    }

    /// The most input images any request sends, where a model's catalog states no limit of its own: as many as
    /// Nano Banana Pro takes, the most of the account's models.
    public static let inputBound = 14

    /// The limit is a bound rather than the model's own: its catalog states none, and the provider's quote refuses
    /// what the model doesn't take.
    public var inputLimitIsBound: Bool {
        input != .none && maxInputs == nil && unstatedInputLimit != nil
    }

    /// The ratio of `aspectRatios` closest to `width` × `height`; the first one when the size is unusable.
    public func nearestAspectRatio(width: Int, height: Int) -> String? {
        guard width > 0, height > 0 else { return aspectRatios.first }
        let target = log(Double(width) / Double(height))
        return aspectRatios.compactMap { ratio in Self.widthOverHeight(ratio).map { (ratio, abs(log($0) - target)) } }
            .min { $0.1 < $1.1 }?.0 ?? aspectRatios.first
    }

    /// "16:9" as 1.78; `nil` for "auto" or anything that isn't two positive numbers.
    public static func widthOverHeight(_ ratio: String) -> Double? {
        let sides = ratio.split(separator: ":").compactMap { Double($0) }
        guard sides.count == 2, sides[0] > 0, sides[1] > 0 else { return nil }
        return sides[0] / sides[1]
    }
}

/// One request for reference images.
public struct ImageRequest: Codable, Sendable, Hashable {
    public var model: String
    public var prompt: String
    public var aspectRatio: String
    /// Images the request makes, one of the model's `variantCounts`.
    public var count: Int
    /// The uploaded images to edit; empty to generate from the prompt.
    public var inputImages: [RemoteAsset]
    /// Values for the model's `settings`, by name: "resolution": "4k". Empty sends the model's defaults.
    public var settings: [String: String]

    public init(
        model: String, prompt: String, aspectRatio: String, count: Int, inputImages: [RemoteAsset] = [],
        settings: [String: String] = [:]
    ) {
        self.model = model
        self.prompt = prompt
        self.aspectRatio = aspectRatio
        self.count = count
        self.inputImages = inputImages
        self.settings = settings
    }

    /// Requests saved before `settings` decode with none.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            model: try container.decode(String.self, forKey: .model),
            prompt: try container.decode(String.self, forKey: .prompt),
            aspectRatio: try container.decode(String.self, forKey: .aspectRatio),
            count: try container.decode(Int.self, forKey: .count),
            inputImages: try container.decode([RemoteAsset].self, forKey: .inputImages),
            settings: try container.decodeIfPresent([String: String].self, forKey: .settings) ?? [:])
    }
}

/// Where a submitted image job is.
public enum ImageJobStatus: Sendable, Hashable {
    case pending
    /// The images, never empty.
    case completed([URL])
    case failed(message: String?)
    case rejected(Rejection)
    case canceled
}

/// Makes reference images: a small service beside `GenerationProvider`, not one of its modes. Its jobs never enter
/// the job engine or the Queue; whoever runs them polls `imageStatus` and counts their price toward the daily cap
/// (`ImageCharge`).
public protocol ImageProvider: Sendable {
    var kind: ProviderKind { get }
    /// The account or key the jobs belong to (`GenerationProvider.owner`), so they are followed again only there.
    var owner: String? { get }
    /// Whether a job can be stopped before it ends; `false` where the connection has no tool that cancels one.
    var canCancel: Bool { get }
    /// The models of this connection, curated ones first; empty when it can't make images.
    func imageModels() async throws -> [ImageModel]
    /// The price of the whole request, the provider's own quote when it gives one.
    func imageEstimate(_ request: ImageRequest) async throws -> Cost
    /// The input of an edit.
    func upload(_ file: PreparedFile) async throws -> RemoteAsset
    /// One job per request, or several when the provider makes a job per image.
    func submitImages(_ request: ImageRequest, idempotencyKey: UUID) async throws -> [RemoteJob]
    func imageStatus(_ job: RemoteJob) async throws -> ImageJobStatus
    /// Throws when the job can't be cancelled any more.
    func cancelImages(_ job: RemoteJob) async throws
}

extension ImageProvider {
    /// Connections can stop a job that hasn't ended yet unless they say otherwise.
    public var canCancel: Bool { true }
}
