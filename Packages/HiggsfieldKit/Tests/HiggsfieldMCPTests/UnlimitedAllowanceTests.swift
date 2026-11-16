import Foundation
import HiggsfieldTestSupport
import Testing

@testable import HiggsfieldMCP

/// `models_explore` `list` pages: model items carrying `supports_unlim`, and a top-level `unlim` block for the
/// account. `CatalogSnapshot` has the live shape; anything else must read as "no allowance".
enum UnlimitedFixture {
    static let page: JSONValue = [
        "models": [
            ["id": "hf_mult_motion_control", "supports_unlim": true],
            ["id": "seedance_2_5", "supports_unlim": false],
            ["id": "kling3_0_motion_control"],
        ],
        "unlim": ["available": true],
    ]
}

@Suite struct UnlimitedAllowanceDecoding {
    @Test func bothSignalsCoverOnlyTheSupportedModel() {
        let allowance = UnlimitedAllowance(pages: [UnlimitedFixture.page])
        #expect(allowance.isAvailable)
        #expect(allowance.supportedModels == ["hf_mult_motion_control"])
        #expect(allowance.covers(.motionControl))
        #expect(!allowance.covers(.seedance25))
        #expect(!allowance.covers(.klingMotionControl))
    }

    @Test func supportWithoutTheAccountsAllowanceCoversNothing() {
        let page: JSONValue = ["models": [["id": "hf_mult_motion_control", "supports_unlim": true]]]
        let allowance = UnlimitedAllowance(pages: [page])
        #expect(allowance.supportedModels == ["hf_mult_motion_control"])
        #expect(!allowance.covers(.motionControl))
    }

    static let blocks: [(block: JSONValue, available: Bool)] = [
        (["available": true], true),
        (["available": true, "remaining": 0], false),
        (["available": true, "active": false], false),
        (["available": "yes"], false),
    ]

    @Test(arguments: blocks)
    func theUnlimBlockSaysYesOnlyInAKnownShape(block: JSONValue, available: Bool) {
        #expect(UnlimitedAllowance.isAvailable(block) == available)
    }

    @Test func useUnlimIsFalseUnlessTheRequestAsksForIt() {
        var request = VideoRequest(model: .motionControl, media: [])
        #expect(request.arguments()["params"]?["use_unlim"] == false)
        request.usesUnlimited = true
        #expect(request.arguments()["params"]?["use_unlim"] == true)
        #expect(request.arguments(getCost: true)["params"]?["use_unlim"] == true)
    }
}

extension Network {
    @Suite struct Unlimited {
        /// `generate_video`'s `outputSchema` sends `cost` only for `get_cost`; one in a submit's answer is still read.
        /// With `count` variants it is the whole request's cost, kept once rather than per variant, and the later
        /// jobs in `results` are the variants.
        @Test func generateReadsTheCreditsTheAnswerNames() async throws {
            let (account, _) = Account.account { _, _ in
                [
                    "results": [["id": "job-1"], ["id": "job-2"]],
                    "cost": ["credits_exact": .number(12.5), "credits": 13],
                ]
            }
            var request = Account.request
            request.count = 2
            let generation = try await account.generate(request)
            #expect(generation.credits == 12.5)
            #expect(generation.variantIDs == ["job-2"])
        }
    }
}
