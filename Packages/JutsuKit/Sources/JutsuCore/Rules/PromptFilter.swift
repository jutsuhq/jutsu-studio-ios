import Foundation

/// English words the providers' moderation refuses, caught before a prompt is sent so a paid job isn't queued only
/// to fail. Whole words only, so "Sussex" or "therapist" pass; bare "sex" passes too ("the opposite sex").
// note: a fixed English list, not moderation; other languages and respelled words still reach the provider.
public enum PromptFilter {
    public static let blockedWords: Set<String> = [
        "nude", "nudes", "nudity", "naked", "nsfw", "porn", "porno", "pornographic", "pornography", "xxx",
        "sexual", "sexually", "erotic", "erotica", "hentai", "topless", "genital", "genitals", "genitalia",
        "penis", "vagina", "nipple", "nipples", "boobs", "orgasm", "masturbate", "masturbation", "fetish", "bdsm",
        "gore", "gory", "dismember", "dismembered", "dismemberment", "decapitate", "decapitated", "decapitation",
        "behead", "beheads", "beheading", "beheaded", "mutilated", "mutilation", "disemboweled",
        "suicide", "suicidal", "rape", "rapes", "raped", "raping", "rapist", "molest", "molested",
        "pedophile", "paedophile", "underage", "incest", "bestiality", "nazi", "nazis", "swastika", "swastikas",
    ]

    /// The blocked words in `prompt`, lowercased, once each in the order they first appear.
    public static func blockedWords(in prompt: String) -> [String] {
        var found: [String] = []
        for token in prompt.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            let word = String(token)
            if blockedWords.contains(word) && !found.contains(word) { found.append(word) }
        }
        return found
    }
}
