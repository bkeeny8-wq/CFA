import XCTest
@testable import CFAL3

/// The playbook is the first GENERATED content in the app: the notes, the
/// Meldrum PDFs and the cycle map all arrived authored and approved. These
/// tests cannot tell you whether a claim about a collar is correct, and they do
/// not pretend to. What they can hold is everything structural around it, so a
/// reader can trust the provenance even where they have to check the substance.
final class InstrumentPlaybookTests: XCTestCase {

    private func loadedContent() throws -> ContentLoader {
        let content = ContentLoader()
        content.load()
        try XCTSkipIf(content.loadError != nil, content.loadError ?? "")
        return content
    }

    private func playbook(_ content: ContentLoader) throws -> InstrumentPlaybook {
        let book = try XCTUnwrap(content.playbook, "instrument_playbook.json is not bundled")
        try XCTSkipIf(book.instruments.isEmpty, "playbook has no instruments yet")
        return book
    }

    /// Deliberately does not skip on an empty playbook: the loader swallows a
    /// decode failure so the entry card can hide, which would make every other
    /// test here pass green on a bundle that ships nothing.
    func testThePlaybookDecodesWithContent() throws {
        let content = try loadedContent()
        let book = try XCTUnwrap(content.playbook, "instrument_playbook.json is not bundled")
        XCTAssertFalse(
            book.instruments.isEmpty,
            "the playbook decoded but is empty, so the section would be invisible"
        )
        XCTAssertFalse(book.families.isEmpty)
    }

    /// Every field the page renders must have something in it. A card with a
    /// heading and no rows reads as a bug, and an instrument with no cues has
    /// lost the field that makes the section worth having.
    func testEveryInstrumentIsComplete() throws {
        let book = try playbook(try loadedContent())
        for item in book.instruments {
            XCTAssertFalse(item.summary.isEmpty, "\(item.key): no summary")
            XCTAssertFalse(item.pros.isEmpty, "\(item.key): no pros")
            XCTAssertFalse(item.cons.isEmpty, "\(item.key): no cons")
            XCTAssertFalse(item.whenToRecommend.isEmpty, "\(item.key): no when-to-recommend")
            XCTAssertFalse(item.whenNotTo.isEmpty, "\(item.key): no when-not-to")
            XCTAssertFalse(item.pitfalls.isEmpty, "\(item.key): no pitfalls")
            XCTAssertFalse(item.cues.isEmpty, "\(item.key): no cues")

            for point in item.pros + item.cons {
                XCTAssertFalse(point.text.trimmingCharacters(in: .whitespaces).isEmpty,
                               "\(item.key): a blank point")
                XCTAssertFalse(point.source.isEmpty, "\(item.key): a point with no source")
            }
            for cue in item.cues {
                XCTAssertFalse(cue.signal.isEmpty, "\(item.key): a cue with no signal")
                XCTAssertFalse(cue.implication.isEmpty, "\(item.key): a cue with no implication")
            }
        }
    }

    func testKeysAreUniqueAndFamiliesAreDeclared() throws {
        let book = try playbook(try loadedContent())
        let keys = book.instruments.map(\.key)
        XCTAssertEqual(Set(keys).count, keys.count, "two instruments share a key")

        let declared = Set(book.families)
        for item in book.instruments {
            XCTAssertTrue(
                declared.contains(item.family),
                "\(item.key) is in family '\(item.family)', which is not declared in families[]"
            )
        }
        // And no declared family renders as an empty heading.
        for family in book.families {
            XCTAssertFalse(
                book.instruments(inFamily: family).isEmpty,
                "family '\(family)' is declared but has no instruments"
            )
        }
        XCTAssertEqual(book.populatedFamilies.count, book.families.count)
    }

    /// A compare chip that resolves to nothing is a control that looks tappable
    /// and opens an empty column.
    ///
    /// Mutation: point one comparesWith at a key that does not exist.
    func testEveryCompareLinkResolves() throws {
        let book = try playbook(try loadedContent())
        var links = 0
        for item in book.instruments {
            for key in item.comparesWith {
                XCTAssertNotNil(
                    book.instrument(key),
                    "\(item.key) compares with '\(key)', which is not an instrument"
                )
                XCTAssertNotEqual(key, item.key, "\(item.key) compares with itself")
                links += 1
            }
            XCTAssertFalse(
                item.comparesWith.isEmpty,
                "\(item.key) offers nothing to compare against"
            )
        }
        XCTAssertGreaterThan(links, book.instruments.count, "the compare graph is too sparse to use")
    }

    /// Provenance has to be real: a point either cites a reading the app has,
    /// or declares itself curriculum material. A source naming a reading that
    /// does not exist is worse than no citation, because the page presents it
    /// as grounded.
    ///
    /// Mutation: change one source to a made-up reading id.
    func testEveryPointSourceIsCurriculumOrARealReading() throws {
        let content = try loadedContent()
        let book = try playbook(content)
        let readings = Set(
            (content.losMaster?.areas ?? []).flatMap(\.readings).map(\.id)
        )
        XCTAssertFalse(readings.isEmpty)

        var cited = 0, curriculum = 0
        for item in book.instruments {
            for point in item.pros + item.cons {
                if point.source == "curriculum" {
                    curriculum += 1
                } else {
                    XCTAssertTrue(
                        readings.contains(point.source),
                        "\(item.key): point cites '\(point.source)', which is not a reading"
                    )
                    cited += 1
                }
            }
        }
        XCTAssertGreaterThan(cited, 0, "nothing is grounded in the reader's own notes")
        print("playbook provenance: \(cited) points cite a reading, \(curriculum) are curriculum")
    }

    /// The house rule the content pipeline enforces everywhere else.
    func testNoEmDashesInUserFacingText() throws {
        let book = try playbook(try loadedContent())
        for item in book.instruments {
            var strings = [item.summary, item.name]
            strings += (item.pros + item.cons).map(\.text)
            strings += item.whenToRecommend + item.whenNotTo + item.pitfalls
            strings += item.cues.flatMap { [$0.signal, $0.implication] }
            for text in strings {
                XCTAssertFalse(
                    text.contains("\u{2014}"),
                    "\(item.key): em dash in \"\(text.prefix(60))\""
                )
            }
        }
    }

    /// Confidence is declared per entry so the page can tell the reader which
    /// ones to check. A value outside the three we render would show nothing.
    func testConfidenceIsOneOfTheThreeValues() throws {
        let book = try playbook(try loadedContent())
        let valid: Set<String> = ["high", "medium", "low"]
        for item in book.instruments {
            XCTAssertTrue(
                valid.contains(item.confidence.lowercased()),
                "\(item.key): confidence '\(item.confidence)' is not high, medium or low"
            )
        }
        // Reported, not asserted: how much of the set the author was sure of is
        // a fact about the content, not a pass/fail condition.
        let low = book.instruments.filter { !$0.isHighConfidence }
        print("playbook confidence: \(low.count) of \(book.instruments.count) below high"
              + (low.isEmpty ? "" : " -> " + low.map(\.key).joined(separator: ", ")))
    }
}
