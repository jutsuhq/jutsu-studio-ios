import Foundation
import Testing

@testable import JutsuCore

@Suite struct ModelConstraintsTests {
    static func table(
        _ model: VideoModel, _ constraints: ModelConstraints, mode: Mode = .motionTransfer
    )
        -> ModelConstraintTable
    {
        ModelConstraintTable(entries: [.init(model: model, mode: mode, constraints: constraints)])
    }

    @Test func theTableReplacesTheConstantsItStates() {
        let table = Self.table(.seedance25, ModelConstraints(maxDuration: 45, maxReferenceImages: 4))
        let limits = VideoModel.seedance25.limits(for: .motionTransfer, constraints: table)
        #expect(limits.duration == 4...45)
        #expect(limits.referenceImages == 1...4)
    }

    @Test func boundsThatContradictEachOtherKeepTheConstants() {
        let table = Self.table(.seedance25, ModelConstraints(minDuration: 40, minReferenceImages: 9))
        #expect(
            VideoModel.seedance25.limits(for: .motionTransfer, constraints: table)
                == .init(
                    referenceImages: 1...8, requiresPreset: false, duration: 4...30))
    }

    @Test func validationChecksAgainstTheTable() {
        let source = SourceClip(
            fileURL: URL(fileURLWithPath: "/tmp/in.mp4"), duration: 60, pixelSize: PixelSize(width: 1280, height: 720),
            range: 0...40)
        let spec = JobSpec(
            mode: .motionTransfer, model: .seedance25, source: source,
            references: [
                LocalImage(
                    fileURL: URL(
                        fileURLWithPath: "/tmp/a.png"))
            ], prompt: "", resolution: .p720)
        #expect(Validation.check(spec) == [.durationTooLong(40)])
        #expect(Validation.check(spec, constraints: Self.table(.seedance25, ModelConstraints(maxDuration: 45))).isEmpty)
    }

    @Test func invalidValuesAreDropped() {
        let constraints = ModelConstraints(
            minDuration: -1, maxDuration: .infinity, minReferenceImages: -2, maxReferenceImages: 3)
        #expect(constraints == ModelConstraints(maxReferenceImages: 3))
    }
}
