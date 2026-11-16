import Foundation
import HiggsfieldMCP

/// The catalog snapshot `docs/mcp-snapshots/2026-10-28.json`: its tool definitions, model pages and live answers,
/// and the checks of a call against them.
public enum CatalogSnapshot {
    // MARK: - Tool definitions

    /// The snapshot file itself, found from this source file's place in the repository.
    /// Parsed with JSONSerialization: decoding all 3 MB as `JSONValue` takes seconds on Linux, so only the parts a
    /// test asks for become `JSONValue` (see `value(of:)`). Immutable once loaded.
    nonisolated(unsafe) static let snapshot: [String: Any]? = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        let file = url.appendingPathComponent("docs/mcp-snapshots/2026-10-28.json")
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }()

    static func value(of part: Any) -> JSONValue? {
        guard let data = try? JSONSerialization.data(withJSONObject: part, options: [.fragmentsAllowed]) else {
            return nil
        }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// A live answer from `docs/mcp-snapshots/live-2026-10-15/<name>.json`: `{tool, arguments, answer}`, the answer
    /// being the call's `structuredContent`, trimmed, with public catalog URLs or `example.com` ones only; an `isError`
    /// answer also has `isError` and its `text`.
    public static func liveAnswer(_ name: String) throws -> LiveAnswer {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        let file = url.appendingPathComponent("docs/mcp-snapshots/live-2026-10-15/\(name).json")
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: file))
        guard let tool = value["tool"]?.stringValue, let arguments = value["arguments"], let answer = value["answer"]
        else { throw MissingTool(name: name) }
        return LiveAnswer(
            tool: tool, arguments: arguments, answer: answer, isError: value["isError"] == true,
            text: value["text"]?.stringValue)
    }

    /// A call the server answered live, and its answer.
    public struct LiveAnswer: Sendable {
        public var tool: String
        public var arguments: JSONValue
        public var answer: JSONValue
        /// The answer was `isError`, with `text` as its first line.
        public var isError = false
        public var text: String?
    }

    struct MissingTool: Error {
        let name: String
    }

    /// A `tools/list` entry of the snapshot as the server sent it (`name`, `description`, `inputSchema`, …), for a
    /// stub to list, so the client matches its role against the real schema.
    public static func tool(_ name: String) throws -> JSONValue {
        let tools = snapshot?["tools"] as? [[String: Any]] ?? []
        guard let entry = tools.first(where: { $0["name"] as? String == name }), let tool = value(of: entry) else {
            throw MissingTool(name: name)
        }
        return tool
    }

    struct MissingModel: Error {
        let id: String
    }

    /// The snapshot's `models_explore {action: "get", model_id: id}` answer (its `structuredContent`), for every
    /// listed video and image model.
    public static func model(_ id: String) throws -> JSONValue {
        let get = (snapshot?["models"] as? [String: Any])?["get"] as? [String: Any]
        guard let content = (get?[id] as? [String: Any])?["structuredContent"], let model = value(of: content),
            model.objectValue != nil
        else {
            throw MissingModel(id: id)
        }
        return model
    }

    /// `generate_video`'s own `params`, which no model schema lists.
    static let toolParams: Set<String> = [
        "model", "prompt", "medias", "use_unlim", "get_cost", "declined_preset_id", "count",
    ]

    /// Where the `params` of a `generate_video` call break the schema `models_explore get` gives for their `model`;
    /// empty when they keep to it. A media role must be one of its `medias[].roles`, `aspect_ratio` one of its
    /// `aspect_ratios`, and every other key one of its `parameters`, of that parameter's type (`number`, `string`,
    /// `bool`, `string_array`) and inside its `options` and `min`…`max`. Throws for a model the snapshot doesn't
    /// describe.
    public static func violations(ofParams params: JSONValue) throws -> [String] {
        guard let object = params.objectValue, let id = object["model"]?.stringValue else { return ["no model"] }
        let model = try model(id)
        var found: [String] = []
        let roles = Set(
            (model["medias"]?.arrayValue ?? []).flatMap { $0["roles"]?.arrayValue ?? [] }.compactMap(\.stringValue))
        for media in object["medias"]?.arrayValue ?? [] {
            let role = media["role"]?.stringValue ?? ""
            if !roles.contains(role) { found.append("\(id): role \(role) isn't one of \(roles.sorted())") }
        }
        let parameters = Dictionary(
            (model["parameters"]?.arrayValue ?? []).compactMap { parameter in
                parameter["name"]?.stringValue.map { ($0, parameter) }
            }, uniquingKeysWith: { first, _ in first })
        for (key, value) in object.sorted(by: { $0.key < $1.key }) where !toolParams.contains(key) {
            if key == "aspect_ratio" {
                if model["aspect_ratios"]?.arrayValue?.contains(value) != true {
                    found.append("\(id): aspect_ratio \(value) isn't listed")
                }
                continue
            }
            guard let parameter = parameters[key] else {
                found.append("\(id): \(key) isn't a parameter")
                continue
            }
            found += violations(of: value, against: parameter, at: "\(id).\(key)")
        }
        return found
    }

    /// One value against one entry of a model's `parameters`.
    static func violations(of value: JSONValue, against parameter: JSONValue, at path: String) -> [String] {
        let typed: Bool =
            switch (parameter["type"]?.stringValue, value) {
            case ("number", .number), ("number", .integer), ("number", .unsignedInteger), ("string", .string),
                ("bool", .bool):
                true
            case ("string_array", .array(let items)): items.allSatisfy { $0.stringValue != nil }
            default: false
            }
        guard typed else { return ["\(path): \(value) isn't a \(parameter["type"] ?? .null)"] }
        var found: [String] = []
        if let options = parameter["options"]?.arrayValue, !options.contains(value) {
            found.append("\(path): \(value) is none of \(options)")
        }
        if let number = value.numberValue {
            if let minimum = parameter["min"]?.numberValue, number < minimum { found.append("\(path): below min") }
            if let maximum = parameter["max"]?.numberValue, number > maximum { found.append("\(path): above max") }
        }
        return found
    }

    /// Where `arguments` break the `inputSchema` of the snapshot's tool `name`; empty when they keep to it. Checks
    /// the parts of JSON Schema the catalog uses: `type`, `properties`, `required`, `additionalProperties: false`,
    /// `enum`, `const`, `anyOf`, `oneOf`, `items`, `minItems`/`maxItems`, `minimum`/`maximum`/`exclusiveMinimum`,
    /// `minLength`/`maxLength` and `pattern`.
    public static func violations(of arguments: JSONValue, sentTo name: String) throws -> [String] {
        guard let schema = try tool(name)["inputSchema"] else { throw MissingTool(name: name) }
        return SchemaCheck.violations(of: arguments, against: schema, at: name)
    }
}

/// A small JSON Schema checker for `CatalogSnapshot.violations(of:sentTo:)`.
enum SchemaCheck {
    static func violations(of value: JSONValue, against schema: JSONValue, at path: String) -> [String] {
        var found: [String] = []
        if let type = schema["type"]?.stringValue, !matches(value, type: type) {
            return ["\(path): not of type \(type)"]
        }
        if let options = schema["enum"]?.arrayValue, !options.contains(value) {
            found.append("\(path): \(value) is none of \(options)")
        }
        if let constant = schema["const"], constant != value {
            found.append("\(path): \(value) isn't \(constant)")
        }
        found += variants(of: value, in: schema, at: path)
        found += bounds(of: value, in: schema, at: path)
        if case .object(let object) = value { found += properties(of: object, in: schema, at: path) }
        if case .array(let items) = value, let itemSchema = schema["items"] {
            for (index, item) in items.enumerated() {
                found += violations(of: item, against: itemSchema, at: "\(path)[\(index)]")
            }
        }
        return found
    }

    static func matches(_ value: JSONValue, type: String) -> Bool {
        switch (type, value) {
        case ("object", .object), ("array", .array), ("string", .string), ("boolean", .bool), ("null", .null),
            ("number", .number), ("number", .integer), ("number", .unsignedInteger), ("integer", .integer),
            ("integer", .unsignedInteger):
            true
        case ("integer", .number(let number)): number == number.rounded()
        default: false
        }
    }

    /// `anyOf` needs one variant to hold, `oneOf` exactly one.
    static func variants(of value: JSONValue, in schema: JSONValue, at path: String) -> [String] {
        var found: [String] = []
        if let anyOf = schema["anyOf"]?.arrayValue,
            !anyOf.contains(where: { violations(of: value, against: $0, at: path).isEmpty })
        {
            found.append("\(path): matches no anyOf variant")
        }
        if let oneOf = schema["oneOf"]?.arrayValue {
            let holding = oneOf.filter { violations(of: value, against: $0, at: path).isEmpty }.count
            if holding != 1 { found.append("\(path): matches \(holding) oneOf variants, not 1") }
        }
        return found
    }

    static func bounds(of value: JSONValue, in schema: JSONValue, at path: String) -> [String] {
        var found: [String] = []
        switch value {
        case .number, .integer, .unsignedInteger:
            guard let number = value.numberValue else { return found }
            if let minimum = schema["minimum"]?.numberValue, number < minimum { found.append("\(path): below minimum") }
            if let maximum = schema["maximum"]?.numberValue, number > maximum { found.append("\(path): above maximum") }
            if let floor = schema["exclusiveMinimum"]?.numberValue, number <= floor {
                found.append("\(path): not above exclusiveMinimum")
            }
        case .string(let text):
            if let minimum = schema["minLength"]?.numberValue, Double(text.count) < minimum {
                found.append("\(path): shorter than minLength")
            }
            if let maximum = schema["maxLength"]?.numberValue, Double(text.count) > maximum {
                found.append("\(path): longer than maxLength")
            }
            if let pattern = schema["pattern"]?.stringValue, text.range(of: pattern, options: .regularExpression) == nil
            {
                found.append("\(path): \"\(text)\" doesn't match the pattern")
            }
        case .array(let items):
            if let minimum = schema["minItems"]?.numberValue, Double(items.count) < minimum {
                found.append("\(path): fewer than minItems")
            }
            if let maximum = schema["maxItems"]?.numberValue, Double(items.count) > maximum {
                found.append("\(path): more than maxItems")
            }
        default:
            break
        }
        return found
    }

    static func properties(of object: [String: JSONValue], in schema: JSONValue, at path: String) -> [String] {
        var found: [String] = []
        let properties = schema["properties"]?.objectValue ?? [:]
        for key in schema["required"]?.arrayValue?.compactMap(\.stringValue) ?? [] where object[key] == nil {
            found.append("\(path): missing \(key)")
        }
        for (key, value) in object.sorted(by: { $0.key < $1.key }) {
            if let property = properties[key] {
                found += violations(of: value, against: property, at: "\(path).\(key)")
            } else if schema["additionalProperties"] == false {
                found.append("\(path): \(key) isn't allowed")
            }
        }
        return found
    }
}
