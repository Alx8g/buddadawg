import Testing
@testable import BarkCore

private func entries(_ lines: [String]) -> [SnippetMatcher.Entry] {
    SnippetMatcher.parse(lines.joined(separator: "\n"))
}

@Test func exactTriggerMatches() {
    let e = entries(["schedule link => Book here: https://cal.com/me"])
    #expect(SnippetMatcher.match("snippet schedule link", entries: e) == "Book here: https://cal.com/me")
}

@Test func caseAndWhitespaceInsensitive() {
    let e = entries(["Email Sig => Best,\\nAlex"])
    #expect(SnippetMatcher.match("  Snippet   EMAIL   sig  ", entries: e) == "Best,\nAlex")
}

@Test func noMatchWithoutPrefixOrUnknownTrigger() {
    let e = entries(["foo => bar"])
    #expect(SnippetMatcher.match("my snippet foo", entries: e) == nil)
    #expect(SnippetMatcher.match("foo", entries: e) == nil)
    #expect(SnippetMatcher.match("snippet unknown", entries: e) == nil)
}

@Test func escapedNewlinesTabsAndBackslashes() {
    let e = entries(["sig => line1\\nline2\\tTabbed\\\\end"])
    #expect(SnippetMatcher.match("snippet sig", entries: e) == "line1\nline2\tTabbed\\end")
}

@Test func malformedLinesIgnored() {
    let e = SnippetMatcher.parse("""
    # comment
    no arrow here
    => missing trigger
    empty =>
    good => works
    """)
    #expect(e.count == 1)
    #expect(SnippetMatcher.match("snippet good", entries: e) == "works")
}
