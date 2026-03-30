import Foundation
import Testing
@testable import ChitChatCore

@Suite("FillerWordFilter Tests")
struct FillerWordFilterTests {

    let filter = FillerWordFilter()

    // MARK: - Basic Removal

    @Test("Removes single filler 'um' from middle of sentence")
    func removesSingleUm() {
        let result = filter.apply("I was um going to the store")
        #expect(result == "I was going to the store")
    }

    @Test("Removes single filler 'uh' from middle of sentence")
    func removesSingleUh() {
        let result = filter.apply("I was uh going to the store")
        #expect(result == "I was going to the store")
    }

    @Test("Removes multi-word filler 'you know'")
    func removesYouKnow() {
        let result = filter.apply("It was you know really great")
        #expect(result == "It was really great")
    }

    @Test("Removes multi-word filler 'I mean'")
    func removesIMean() {
        let result = filter.apply("I mean the weather is nice")
        #expect(result == "The weather is nice")
    }

    // MARK: - Word Boundary Safety

    @Test("Does not remove 'um' from 'umbrella'")
    func preservesUmbrella() {
        let result = filter.apply("I need an umbrella")
        #expect(result == "I need an umbrella")
    }

    @Test("Does not remove 'um' from 'assume'")
    func preservesAssume() {
        let result = filter.apply("I assume that is correct")
        #expect(result == "I assume that is correct")
    }

    @Test("Does not remove 'er' from 'error' or 'every'")
    func preservesWordsContainingEr() {
        let result = filter.apply("There was an error in every report")
        #expect(result == "There was an error in every report")
    }

    @Test("Does not remove 'ah' from 'ahead'")
    func preservesAhead() {
        let result = filter.apply("Go ahead and start")
        #expect(result == "Go ahead and start")
    }

    // MARK: - Case Insensitivity

    @Test("Removes 'Um' with capital U")
    func removesCapitalUm() {
        let result = filter.apply("Um I think so")
        #expect(result == "I think so")
    }

    @Test("Removes 'You Know' with mixed case")
    func removesMixedCaseYouKnow() {
        let result = filter.apply("It was You Know pretty good")
        #expect(result == "It was pretty good")
    }

    // MARK: - Position Edge Cases

    @Test("Removes filler at start and capitalizes next word")
    func fillerAtStart() {
        let result = filter.apply("Um the meeting is at three")
        #expect(result == "The meeting is at three")
    }

    @Test("Removes filler at end")
    func fillerAtEnd() {
        let result = filter.apply("I think so um")
        #expect(result == "I think so")
    }

    @Test("Removes multiple consecutive fillers")
    func multipleConsecutiveFillers() {
        let result = filter.apply("I um uh think you know it works")
        #expect(result == "I think it works")
    }

    // MARK: - Empty and No-Op

    @Test("Returns empty string when all words are fillers")
    func allFillers() {
        let result = filter.apply("um uh you know")
        #expect(result == "")
    }

    @Test("Returns empty string for empty input")
    func emptyInput() {
        let result = filter.apply("")
        #expect(result == "")
    }

    @Test("Returns text unchanged when no fillers present")
    func noFillers() {
        let result = filter.apply("The weather is nice today")
        #expect(result == "The weather is nice today")
    }

    // MARK: - Spacing and Punctuation Cleanup

    @Test("Cleans up double spaces after removal")
    func cleansDoubleSpaces() {
        let result = filter.apply("I um think um it works")
        #expect(!result.contains("  "))
        #expect(result == "I think it works")
    }

    @Test("Cleans up dangling commas after filler removal")
    func cleansDanglingCommas() {
        let result = filter.apply("I went to, um, the store")
        #expect(result == "I went to, the store")
    }

    @Test("Removes hyphenated fillers")
    func removesHyphenatedFillers() {
        let result = filter.apply("uh-huh that sounds right")
        #expect(result == "That sounds right")
    }

    // MARK: - Sentence Capitalization

    @Test("Re-capitalizes after sentence-ending punctuation")
    func recapitalizesAfterPeriod() {
        let result = filter.apply("That was great. um the next one is better.")
        #expect(result == "That was great. The next one is better.")
    }
}
