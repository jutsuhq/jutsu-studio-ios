import HiggsfieldProviders
import JutsuCore

/// What the active connection offers beyond generating videos; each is `nil` while disconnected or when the
/// connection doesn't have it (an API key has none of these).
extension AppEnvironment {
    var imageProvider: (any ImageProvider)? { provider as? any ImageProvider }
    var generationHistory: (any GenerationHistory)? { provider as? any GenerationHistory }
    var generationLikes: (any GenerationLikes)? { provider as? any GenerationLikes }
    var accountUploads: (any AccountUploads)? { provider as? any AccountUploads }
    var voiceLibrary: (any VoiceLibrary)? { provider as? any VoiceLibrary }
    var viralityScorer: (any ViralityScoring)? { provider as? any ViralityScoring }

    var characterMaker: (any CharacterSheetMaker)? {
        guard HiggsfieldMCPProvider.offersCharacterSheets else { return nil }
        return provider as? any CharacterSheetMaker
    }
}
