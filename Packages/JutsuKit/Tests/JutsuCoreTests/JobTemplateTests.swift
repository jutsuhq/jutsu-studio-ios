import Foundation
import Testing

@testable import JutsuCore

@Test func aDecodedTemplateKeepsThePresetOnlyForAModeThatTakesOne() throws {
    let template = JobTemplate(name: "Swap", mode: .motionTransfer, resolution: .p720)
    var fields = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(template)) as? [String: Any])
    fields["presetID"] = UUID().uuidString
    let saved = try JSONSerialization.data(withJSONObject: fields)
    #expect(try JSONDecoder().decode(JobTemplate.self, from: saved).presetID == nil)
}
