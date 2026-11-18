import Testing
import BarkCore

// SpokenCommands is conservative by design: the false-positive cases below matter as much
// as the positives, because a mis-fired command silently eats or alters dictated words.

@Test func scratchThatDiscardsWholeUtterance() {
    for input in ["scratch that", "Scratch that", "Scratch that.", " scratch that! "] {
        let result = SpokenCommands.parse(input)
        #expect(result.shouldDiscard)
        #expect(result.text == "")
        #expect(result.actions == [.discard])
    }
}

@Test func scratchThatInsideSpeechStaysText() {
    for input in ["scratch that itch for me", "please scratch that", "scratch that idea and start over"] {
        let result = SpokenCommands.parse(input)
        #expect(!result.shouldDiscard)
        #expect(result.actions.isEmpty)
        #expect(result.text == input)
    }
}

@Test func trailingNewParagraphAndNewLineInsertBreaks() {
    #expect(SpokenCommands.parse("Hello world new paragraph").text == "Hello world\n\n")
    #expect(SpokenCommands.parse("Hello world new paragraph").actions == [.insertParagraphBreak])
    #expect(SpokenCommands.parse("Hello world new line").text == "Hello world\n")
    #expect(SpokenCommands.parse("Hello world new line").actions == [.insertLineBreak])
    // Terminal punctuation on the command, or on the sentence before it, is not in the way.
    #expect(SpokenCommands.parse("Hello world new paragraph.").text == "Hello world\n\n")
    #expect(SpokenCommands.parse("Hello world. New paragraph").text == "Hello world.\n\n")
    // A comma that only introduced the command is dropped with it.
    #expect(SpokenCommands.parse("Hello world, new line").text == "Hello world\n")
    // Repeated trailing commands stack in spoken order.
    #expect(SpokenCommands.parse("Hello new line new line").text == "Hello\n\n")
    #expect(SpokenCommands.parse("Hello new line new paragraph").text == "Hello\n\n\n")
    #expect(SpokenCommands.parse("Hello new line new paragraph").actions == [.insertLineBreak, .insertParagraphBreak])
}

@Test func standaloneBreakCommandsPasteJustTheBreak() {
    #expect(SpokenCommands.parse("new paragraph").text == "\n\n")
    #expect(SpokenCommands.parse("New paragraph.").actions == [.insertParagraphBreak])
    #expect(SpokenCommands.parse("new line").text == "\n")
    #expect(SpokenCommands.parse("new line").actions == [.insertLineBreak])
}

@Test func newLineAndParagraphInsideSentencesStayText() {
    for input in [
        "a new line of work",                       // the canonical false positive
        "she started a new line of work in june",
        "the new paragraph in the contract is shorter",
        "a new paragraph starts here in the draft", // leading, not trailing: not a command
        "add a new line",                           // trailing, but an article precedes it
        "start the new paragraph",
        "they launched a brand new line",
        "this new line",
        "new paragraph energy is what we need",     // leading position never triggers breaks
    ] {
        let result = SpokenCommands.parse(input)
        #expect(result.actions.isEmpty, "false positive on: \(input)")
        #expect(result.text == input)
    }
}

@Test func leadingBulletPointPrefixesABullet() {
    let result = SpokenCommands.parse("bullet point buy milk")
    #expect(result.text == "• buy milk")
    #expect(result.actions == [.bulletPoint])
    // A separator dictated after the command is dropped, and case does not matter.
    #expect(SpokenCommands.parse("Bullet point, buy milk").text == "• buy milk")
    #expect(SpokenCommands.parse("Bullet point buy milk.").text == "• buy milk.")
    // A bare command still leaves a bullet to type after.
    #expect(SpokenCommands.parse("bullet point").text == "•")
    #expect(SpokenCommands.parse("bullet point").actions == [.bulletPoint])
}

@Test func bulletPointInsideSpeechStaysText() {
    for input in [
        "the bullet point said revenue grew",
        "add a bullet point about pricing",   // mid-sentence: talking about a bullet
        "bullet points help scanning",       // plural is a noun, not the command
        "that bullet point",
    ] {
        let result = SpokenCommands.parse(input)
        #expect(result.actions.isEmpty, "false positive on: \(input)")
        #expect(result.text == input)
    }
}

@Test func bulletPointCombinesWithTrailingBreak() {
    let result = SpokenCommands.parse("bullet point buy milk new line")
    #expect(result.text == "• buy milk\n")
    #expect(result.actions == [.bulletPoint, .insertLineBreak])
}

@Test func ordinaryAndEmptyTextPassThroughUnchanged() {
    #expect(SpokenCommands.parse("") == SpokenCommands.Result(text: "", actions: []))
    #expect(SpokenCommands.parse("   ") == SpokenCommands.Result(text: "", actions: []))
    let input = "Save the file.  Then run 12 tests at 3:45 pm."
    let result = SpokenCommands.parse(input)
    #expect(result.actions.isEmpty)
    #expect(result.text == input)  // untouched, not re-joined, when nothing matched
}

@Test func trailingPunctuationCommandsInsertMarks() {
    #expect(SpokenCommands.parse("Hello world comma").text == "Hello world,")
    #expect(SpokenCommands.parse("Hello world period").text == "Hello world.")
    #expect(SpokenCommands.parse("Hello world full stop").text == "Hello world.")
    #expect(SpokenCommands.parse("Hello world question mark").text == "Hello world?")
    #expect(SpokenCommands.parse("Hello world exclamation mark").text == "Hello world!")
    #expect(SpokenCommands.parse("Hello world exclamation point").text == "Hello world!")
    #expect(SpokenCommands.parse("Hello world colon").text == "Hello world:")
    #expect(SpokenCommands.parse("Hello world semicolon").text == "Hello world;")
    #expect(SpokenCommands.parse("Hello world ellipsis").text == "Hello world…")
    #expect(SpokenCommands.parse("Hello world dot dot dot").text == "Hello world…")
    #expect(SpokenCommands.parse("Hello world open quote").text == "Hello world“")
    #expect(SpokenCommands.parse("Hello world close quote").text == "Hello world”")
    #expect(SpokenCommands.parse("Hello world comma").actions == [.insertPunctuation(",")])
    // Case and a joiner comma on the command word don't get in the way.
    #expect(SpokenCommands.parse("Hello world, Comma").text == "Hello world,")
    // Standalone commands paste just the mark.
    #expect(SpokenCommands.parse("comma").text == ",")
    #expect(SpokenCommands.parse("Question Mark").text == "?")
    #expect(SpokenCommands.parse("dot dot dot").text == "…")
}

@Test func punctuationCommandsComposeWithBreaksAndBullets() {
    let result = SpokenCommands.parse("hello comma new line")
    #expect(result.text == "hello,\n")
    #expect(result.actions == [.insertPunctuation(","), .insertLineBreak])
    #expect(SpokenCommands.parse("hello new line comma").text == "hello\n,")
    #expect(SpokenCommands.parse("bullet point buy milk comma").text == "• buy milk,")
    #expect(SpokenCommands.parse("bullet point buy milk comma").actions == [.bulletPoint, .insertPunctuation(",")])
    // Repeated commands stack in spoken order.
    #expect(SpokenCommands.parse("Hello comma period").text == "Hello,.")
    #expect(SpokenCommands.parse("Hello comma period").actions == [.insertPunctuation(","), .insertPunctuation(".")])
}

@Test func punctuationCommandsInsideSentencesStayText() {
    for input in [
        "I said period at the end",
        "a comma splice",
        "the semicolon is mightier than the comma",
        "the Victorian period",        // capitalised noun adjunct: a phrase, not a command
        "the grace period",            // common "… period" noun phrase
        "serial comma",                // ditto for "… comma"
        "a question mark",
        "the question mark",
        "an exclamation point",
        "the full stop",
        "a close quote",
        "the colon",
        "the ellipsis",
        "Periods are nice",            // plural is a noun, not the command
        "comma separated values rock", // mid-sentence: never triggers
        "she paused, then continued",
    ] {
        let result = SpokenCommands.parse(input)
        #expect(result.actions.isEmpty, "false positive on: \(input)")
        #expect(result.text == input)
    }
}

@Test func punctuationCommandAlreadyCarryingPunctuationStaysText() {
    // The mark was dictated alongside the words — firing would double or eat it.
    for input in [
        "question mark?",
        "Hello question mark?",
        "Hello period.",
        "Hello comma!",
        "exclamation mark!",
        "Comma.",
        "dot dot dot.",
    ] {
        let result = SpokenCommands.parse(input)
        #expect(result.actions.isEmpty, "false positive on: \(input)")
        #expect(result.text == input)
    }
    // But breaks still tolerate their own trailing punctuation, and a sentence break
    // before the command doesn't block it.
    #expect(SpokenCommands.parse("Hello world. Comma").text == "Hello world.,")
    #expect(SpokenCommands.parse("Buy milk. Eggs comma").text == "Buy milk. Eggs,")
}

@Test func commandsComposeWithTheFormatter() {
    // The app pipeline formats first (Formatter would collapse our \n), then parses.
    let formatted = DictationFormatter.format("hello world new paragraph")
    #expect(SpokenCommands.parse(formatted).text == "Hello world\n\n")
    #expect(SpokenCommands.parse(DictationFormatter.format("scratch that")).shouldDiscard)
    // Formatting must not turn ordinary speech into a command.
    let speech = DictationFormatter.format("a new line of work")
    #expect(SpokenCommands.parse(speech).actions.isEmpty)
}
