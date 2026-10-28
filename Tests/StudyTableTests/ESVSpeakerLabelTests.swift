import XCTest
@testable import StudyTable

/// Regression fixture: a real response from the ESV API for Song of Solomon 1, fetched
/// 2026-09-22 after a live bug report — bare speaker labels ("She"/"He"/"Others") print as
/// their own blank-line-isolated paragraph with no verse number, and were bleeding into the
/// END of the preceding verse's text ("...your companions? He"). This is the exact raw text
/// that exposed it, not a synthesized approximation.
final class ESVSpeakerLabelTests: XCTestCase {
    static let rawSongOfSolomon1 = """
[1] The Song of Songs, which is Solomon’s.

    She
    
    [2] Let him kiss me with the kisses of his mouth!
    For your love is better than wine;
    [3]     your anointing oils are fragrant;
    your name is oil poured out;
        therefore virgins love you.
    [4] Draw me after you; let us run.
        The king has brought me into his chambers.
    
    
    Others
    
    We will exult and rejoice in you;
        we will extol your love more than wine;
        rightly do they love you.
    
    
    She
    
    [5] I am very dark, but lovely,
        O daughters of Jerusalem,
    like the tents of Kedar,
        like the curtains of Solomon.
    [6] Do not gaze at me because I am dark,
        because the sun has looked upon me.
    My mother’s sons were angry with me;
        they made me keeper of the vineyards,
        but my own vineyard I have not kept!
    [7] Tell me, you whom my soul loves,
        where you pasture your flock,
        where you make it lie down at noon;
    for why should I be like one who veils herself
        beside the flocks of your companions?
    
    
        He
    
    [8] If you do not know,
        O most beautiful among women,
    follow in the tracks of the flock,
        and pasture your young goats
        beside the shepherds’ tents.
    
    
    [9] I compare you, my love,
        to a mare among Pharaoh’s chariots.
    [10] Your cheeks are lovely with ornaments,
        your neck with strings of jewels.
    
    
    Others
    
    [11] We will make for you ornaments of gold,
        studded with silver.
    
    
    She
    
    [12] While the king was on his couch,
        my nard gave forth its fragrance.
    [13] My beloved is to me a sachet of myrrh
        that lies between my breasts.
    [14] My beloved is to me a cluster of henna blossoms
        in the vineyards of Engedi.
    
    
    He
    
    [15] Behold, you are beautiful, my love;
        behold, you are beautiful;
        your eyes are doves.
    
    
    She
    
    [16] Behold, you are beautiful, my beloved, truly delightful.
    Our couch is green;
    [17]     the beams of our house are cedar;
        our rafters are pine.
    


"""

    func testSpeakerLabelsAreStrippedNotAppendedToThePrecedingVerse() {
        let verses = VerseMarkerParser.split(Self.rawSongOfSolomon1)
        let byNumber = Dictionary(uniqueKeysWithValues: verses.map { ($0.n, $0.t) })

        // These three are the exact verses the live bug report showed corrupted.
        XCTAssertEqual(byNumber[7], "Tell me, you whom my soul loves, where you pasture your flock, where you make it lie down at noon; for why should I be like one who veils herself beside the flocks of your companions?")
        XCTAssertEqual(byNumber[10], "Your cheeks are lovely with ornaments, your neck with strings of jewels.")
        XCTAssertEqual(byNumber[14], "My beloved is to me a cluster of henna blossoms in the vineyards of Engedi.")

        for (number, text) in byNumber {
            XCTAssertFalse(text.hasSuffix(" He"), "verse \(number) still has a trailing speaker label: \(text)")
            XCTAssertFalse(text.hasSuffix(" She"), "verse \(number) still has a trailing speaker label: \(text)")
            XCTAssertFalse(text.hasSuffix(" Others"), "verse \(number) still has a trailing speaker label: \(text)")
        }
    }

    func testAllSeventeenVersesOfSongOfSolomon1StillParseWithRealContent() {
        let verses = VerseMarkerParser.split(Self.rawSongOfSolomon1)
        XCTAssertEqual(verses.map(\.n), Array(1...17), "the speaker-label fix must not drop or renumber a real verse")
        for verse in verses {
            XCTAssertGreaterThan(verse.t.count, 5, "verse \(verse.n) lost its real content")
        }
    }

    func testFirstVerseTextIsUncontaminatedByTheFollowingSheLabel() {
        let verses = VerseMarkerParser.split(Self.rawSongOfSolomon1)
        XCTAssertEqual(verses.first { $0.n == 1 }?.t, "The Song of Songs, which is Solomon\u{2019}s.")
    }

    // MARK: - Structural edge cases for the stripping heuristic itself

    func testOrdinaryTextIsNeverMistakenForASpeakerLabel() {
        // A short, ordinary, single-verse passage with no paragraph break at all must be untouched.
        XCTAssertEqual(VerseMarkerParser.split("[1] In the beginning was the Word.").first?.t, "In the beginning was the Word.")
        // A real trailing proper name that is NOT isolated by a blank-paragraph break must survive.
        let noBreak = "[1] Jesus said to Simon Peter, Simon."
        XCTAssertEqual(VerseMarkerParser.split(noBreak).first?.t, "Jesus said to Simon Peter, Simon.")
    }

    func testAnIsolatedButLowercaseTrailingWordIsNotStripped() {
        // The heuristic requires capitalization; a lowercase trailing paragraph is real content,
        // not a label, and must be preserved (guards against over-eager stripping).
        let text = "[1] Some content here.\n\n    amen\n\n[2] Next verse."
        XCTAssertEqual(VerseMarkerParser.split(text).first?.t, "Some content here. amen")
    }
}
