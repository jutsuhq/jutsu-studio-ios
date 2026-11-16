import Foundation
import Testing

@testable import JutsuCore

/// Jobs stored before Edit and Extend existed decode unchanged, and the new modes round-trip.
@Test func storedModesStillDecode() throws {
    let decoded = try JSONDecoder().decode([Mode].self, from: Data(#"["motionTransfer","restyle","objectSwap"]"#.utf8))
    #expect(decoded == [.motionTransfer, .restyle, .objectSwap])
    let new = try JSONDecoder().decode([Mode].self, from: JSONEncoder().encode([Mode.edit, .extend]))
    #expect(new == [.edit, .extend])
}
