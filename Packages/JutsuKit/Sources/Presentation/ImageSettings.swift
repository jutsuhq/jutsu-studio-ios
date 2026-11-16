import Foundation
import JutsuCore

extension ImageModel.Setting {
    /// Every value is a size, "1k" or "1.5k": Soul 2's `quality` picks a resolution too.
    public var isSize: Bool {
        options.allSatisfy { $0.range(of: #"^\d+(\.\d+)?k$"#, options: [.regularExpression, .caseInsensitive]) != nil }
    }

    /// "Resolution" or "Quality".
    public var title: String {
        if isSize || name == "resolution" { return String(localized: "Resolution", bundle: .module) }
        if name == "quality" { return String(localized: "Quality", bundle: .module) }
        return name.capitalized
    }

    /// "4K", "1.5K"; "Low", "High".
    public func optionTitle(_ value: String) -> String {
        if isSize { return value.uppercased() }
        switch value.lowercased() {
        case "low": return String(localized: "Low", bundle: .module)
        case "medium": return String(localized: "Medium", bundle: .module)
        case "high": return String(localized: "High", bundle: .module)
        case "basic": return String(localized: "Basic", bundle: .module)
        default: return value.capitalized
        }
    }
}

extension ImageModel {
    /// "Up to 4K · Edits images", under the model's name; `nil` with nothing to say.
    public var summary: String? {
        var parts: [String] = []
        if let size = settings.first(where: \.isSize)?.options.last {
            parts.append(String(localized: "Up to \(size.uppercased())", bundle: .module))
        }
        switch input {
        case .none: break
        case .optional: parts.append(String(localized: "Edits images", bundle: .module))
        case .required: parts.append(String(localized: "Edits an image", bundle: .module))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

extension ReferenceGenerator {
    /// The value the request sends for `setting`: the one picked when the model offers it, else its default.
    public func settingValue(_ setting: ImageModel.Setting) -> String {
        chosenSettings[setting.name].flatMap { setting.options.contains($0) ? $0 : nil } ?? setting.defaultValue
    }

    /// Every setting of the model with the value it sends.
    public var settingValues: [String: String] {
        Dictionary(uniqueKeysWithValues: (model?.settings ?? []).map { ($0.name, settingValue($0)) })
    }
}
