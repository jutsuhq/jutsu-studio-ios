import Testing

@testable import JutsuCore

@Test func blockedWordsAreWholeWordsInEveryForm() {
    #expect(PromptFilter.blockedWords(in: "Nazis beheading a man, NUDE") == ["nazis", "beheading", "nude"])
    #expect(PromptFilter.blockedWords(in: "a therapist in Sussex meets the opposite sex").isEmpty)
}
