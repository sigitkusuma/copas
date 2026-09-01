import Testing

@testable import Copas

struct CodeHeuristicTests {

    @Test(arguments: [
        "func add(_ a: Int) -> Int { a + 1 }",
        "SELECT preview FROM clip WHERE kind = 1;",
        "{\"name\": \"copas\", \"version\": [1, 2]}",
        "if (x > 0) {\n  return true;\n}",
        "<div class=\"card\"><span>hi</span></div>",
        "cd /tmp && ./run.sh --verbose | tee out.log",
    ])
    func codeIsRecognised(snippet: String) {
        #expect(CodeHeuristic.looksLikeCode(snippet), "expected code: \(snippet)")
    }

    @Test(arguments: [
        "Remember to pick up milk on the way home tonight.",
        "The quick brown fox jumps over the lazy dog.",
        "Meeting moved to Thursday — same room, same time.",
        "@sigit #release shipping the new build today",
        "Sigit Kusuma, 12 Jalan Merdeka, Bandung",
    ])
    func proseIsLeftAlone(sentence: String) {
        #expect(!CodeHeuristic.looksLikeCode(sentence), "expected prose: \(sentence)")
    }

    /// A known edge of a structural heuristic: a command made only of words and
    /// hyphens has nothing to find. Monospacing it would be nicer, but every rule
    /// that catches it also catches hyphenated prose.
    @Test func aBareCommandLineIsNotDetected() {
        #expect(!CodeHeuristic.looksLikeCode("git rebase --onto main feature~3 feature"))
    }

    /// Four words in a monospaced face because one of them was "C++" reads as a
    /// bug, so anything too short to judge is left alone.
    @Test func shortSnippetsAreNotGuessedAt() {
        #expect(!CodeHeuristic.looksLikeCode("C++"))
        #expect(!CodeHeuristic.looksLikeCode("a = 1"))
        #expect(!CodeHeuristic.looksLikeCode(""))
    }

    /// Indentation across several lines: prose wraps, code is arranged.
    @Test func arrangedLinesCountAsCode() {
        #expect(CodeHeuristic.looksLikeCode("""
            fruits:
              apples
              oranges
            """))
    }
}
