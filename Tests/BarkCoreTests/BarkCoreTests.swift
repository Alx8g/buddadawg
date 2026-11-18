import Testing
@testable import BarkCore

/// Regression for the overlay jitter: with `sin(t * speed * (1 + k*level))`, the phase jump per
/// frame grows with elapsed `t`. The warped clocks must keep per-frame phase change bounded by
/// rate * dt no matter how long the app has been animating.
@Test func warpedPhaseStaysContinuousAfterLongRun() {
    var clock = PhaseClock()
    let dt: Float = 1.0 / 120
    for i in 0..<(7200 * 120) {
        let level: Float = (i / 30) % 2 == 0 ? 0.85 : 0.05
        clock.advance(dt: dt, level: level, swell: level)
    }
    var lastShaft = clock.shaftTime, lastBump = clock.bumpTime
    for i in 0..<240 {
        let target: Float = (i / 12) % 2 == 0 ? 0.9 : 0.0
        clock.advance(dt: dt, level: target, swell: target)
        // Fastest shaft speed .13 warped by (1 + 1.5*level); fastest bump 1.93 warped by (.7 + .8*level).
        #expect(abs(clock.shaftTime - lastShaft) * 0.13 <= 0.13 * (1 + 1.5) * dt + 0.0001)
        #expect(abs(clock.bumpTime - lastBump) * 1.93 <= 1.93 * (0.7 + 0.8) * dt + 0.0001)
        lastShaft = clock.shaftTime; lastBump = clock.bumpTime
    }
}

@Test func wrapWhileHiddenKeepsValuesFiniteAndSmall() {
    var clock = PhaseClock()
    for _ in 0..<(8000 * 120) { clock.advance(dt: 1.0 / 120, level: 0.5, swell: 0.5) }
    clock.wrapIfNeeded()
    #expect(clock.time < 7200)
    #expect(clock.time.isFinite && clock.shaftTime.isFinite && clock.bumpTime.isFinite)
}

@Test func capitalisation() {
    #expect(DictationFormatter.format("save the file and run the tests again") == "Save the file and run the tests again")
    #expect(DictationFormatter.format("hello world. this is fine! right? yes") == "Hello world. This is fine! Right? Yes")
    #expect(DictationFormatter.format("i said i'm ready") == "I said I'm ready")
}

@Test func punctuationSpacing() {
    #expect(DictationFormatter.format("an800 .4 is loud , really loud") == "An800.4 is loud, really loud")
    #expect(DictationFormatter.format("too   many    spaces") == "Too many spaces")
}

@Test func numberWordsBecomeDigits() {
    #expect(DictationFormatter.format("send one thousand two hundred and fifty dollars") == "Send 1250 dollars")
    #expect(DictationFormatter.format("about forty thousand watts") == "About 40000 watts")
    #expect(DictationFormatter.format("thirty six hundred point one amplifiers") == "3600.1 amplifiers")
    #expect(DictationFormatter.format("invoice number four thousand eighty-two") == "Invoice number 4082")
}

@Test func timesBecomeClockTimes() {
    #expect(DictationFormatter.format("at three forty five pm tomorrow") == "At 3:45 pm tomorrow")
    #expect(DictationFormatter.format("at three forty five p. m. tomorrow") == "At 3:45 pm tomorrow")
    #expect(DictationFormatter.format("at three forty-five p. m. send it") == "At 3:45 pm send it")
}

@Test func numbersRespectSentenceBoundariesAndIncompleteDecimals() {
    #expect(DictationFormatter.format("twenty. five dollars") == "Twenty. 5 dollars")
    #expect(DictationFormatter.format("twenty! five dollars") == "Twenty! 5 dollars")
    #expect(DictationFormatter.format("twenty? five dollars") == "Twenty? 5 dollars")
    #expect(DictationFormatter.format("one point") == "One point")
    #expect(DictationFormatter.format("one point. five dollars") == "One point. 5 dollars")
    #expect(DictationFormatter.format("one point five") == "1.5")
    #expect(DictationFormatter.format("one point five. six dollars") == "1.5. 6 dollars")
    #expect(DictationFormatter.format("one hundred-point scale") == "One hundred-point scale")
    #expect(DictationFormatter.format("two hundred-point five") == "200.5")
    #expect(DictationFormatter.format("") == "")
}

@Test func singleNumberWordsAreLeftAlone() {
    #expect(DictationFormatter.format("one of these days two things happen") == "One of these days two things happen")
    #expect(DictationFormatter.format("it costs five dollars") == "It costs 5 dollars")
}

@Test func countingListsStayWords() {
    #expect(DictationFormatter.format("one two three check check three two one") == "One two three check check three two one")
    #expect(DictationFormatter.format("number one number two number three") == "Number one number two number three")
}

@Test func alreadyFormattedTextIsStable() {
    #expect(DictationFormatter.format("Save the file. Then run 12 tests at 3:45 pm.") == "Save the file. Then run 12 tests at 3:45 pm.")
}

@Test func encodedLength() {
    #expect(Transcriber.encodedLength(801) == 101)
    #expect(Transcriber.encodedLength(1501) == 188)
    #expect(Transcriber.encodedLength(1) == 1)
}

@Test func shortAudioIsOneSegment() {
    let audio = [Float](repeating: 0.1, count: 16000 * 5)
    #expect(Transcriber.segments(audio, longestWindow: 15).count == 1)
}

@Test func longAudioCutsNearQuietRegion() {
    // 40 s: loud tone with a silent second at 12 s; the first cut must land in that silence.
    var audio = [Float](repeating: 0.4, count: 16000 * 40)
    for i in (16000 * 12)..<(16000 * 13) { audio[i] = 0 }
    let parts = Transcriber.segments(audio, longestWindow: 15)
    #expect(parts.count >= 3)
    let firstCutSeconds = Double(parts[0].count) / 16000
    #expect(firstCutSeconds > 11.5)
    #expect(firstCutSeconds < 13.5)
    #expect(parts.reduce(0) { $0 + $1.count } == audio.count)
}
