import XCTest
@testable import CFAL3

/// The Cycle Map is authored content reached through name matching against
/// los_master. Both halves fail silently: a decode slip hides the entry card,
/// and an unresolvable reading title renders a dead badge or an empty practice
/// pool. These walk the real bundle.
final class CycleMapTests: XCTestCase {

    private func loadedContent() throws -> ContentLoader {
        let content = ContentLoader()
        content.load()
        try XCTSkipIf(content.loadError != nil, content.loadError ?? "")
        return content
    }

    private func map(_ content: ContentLoader) throws -> CycleMap {
        try XCTUnwrap(content.cycleMap, "cycle_map.json is not in the app bundle")
    }

    /// Deliberately does not skip: the loader swallows a decode failure so the
    /// feature can hide itself, which would make every other test here pass
    /// green on a bundle that no longer ships the file.
    func testTheCycleMapDecodes() throws {
        let content = try loadedContent()
        let map = try map(content)

        XCTAssertEqual(map.phases.count, 5)
        XCTAssertEqual(map.assets.count, 9)
        XCTAssertEqual(map.assetChains.count, 9)
        XCTAssertEqual(map.assetTraps.count, 9)
        XCTAssertEqual(map.frameworksStatic.count, 8)
        XCTAssertEqual(map.movesStatic.count, 5)
        XCTAssertEqual(
            map.phases.map(\.name),
            ["Initial recovery", "Early expansion", "Late expansion", "Slowdown", "Contraction"]
        )
    }

    /// Stances and mechanisms are positional against `assets`, and moves are
    /// positional against `movesStatic`. A short array would silently drop the
    /// last asset's panel or a move's worked numbers.
    func testEveryPhaseIsPositionallyCompleteAgainstItsAssetsAndMoves() throws {
        let map = try map(try loadedContent())
        for phase in map.phases {
            XCTAssertEqual(phase.stances.count, map.assets.count, "\(phase.name): stances")
            XCTAssertEqual(phase.mechanisms.count, map.assets.count, "\(phase.name): mechanisms")
            XCTAssertEqual(phase.moves.count, map.movesStatic.count, "\(phase.name): moves")
            for stance in phase.stances {
                XCTAssertTrue(["OW", "N", "UW"].contains(stance),
                              "\(phase.name): unknown stance '\(stance)'")
            }
        }
    }

    /// THE acceptance check: the practice CTA must never open an empty
    /// sitting. Mutation: drop R1/R2 from `readingIDs` and phases whose moves
    /// all point at one thinly-covered reading fall to zero.
    func testEveryPhaseHasANonEmptyPracticePool() throws {
        let content = try loadedContent()
        let map = try map(content)

        for phase in map.phases {
            let ids = CycleMapLinks.practiceQuestionIDs(phase: phase, map: map, content: content)
            XCTAssertFalse(ids.isEmpty, "\(phase.name): the practice CTA would open an empty sitting")
            XCTAssertEqual(Set(ids).count, ids.count, "\(phase.name): the pool repeats a question")
            for id in ids {
                XCTAssertNotNil(content.question(id: id), "\(phase.name): '\(id)' is not in the bank")
            }
        }
    }

    /// Every reading tag a move shows must resolve, or the badge is a control
    /// that looks tappable and is not.
    func testEveryReadingTagUsedByAMoveResolvesToARealReading() throws {
        let content = try loadedContent()
        let map = try map(content)

        var checked = 0
        for phase in map.phases {
            for move in phase.moves {
                XCTAssertNotNil(
                    map.readingLinks[move.readingTag],
                    "\(phase.name)/\(move.name): tag '\(move.readingTag)' is not in reading_links"
                )
                XCTAssertNotNil(
                    CycleMapLinks.reading(forTag: move.readingTag, map: map, content: content),
                    "tag '\(move.readingTag)' -> '\(map.readingLinks[move.readingTag] ?? "?")' "
                    + "matches no reading in los_master"
                )
                checked += 1
            }
        }
        XCTAssertEqual(checked, 25, "5 phases x 5 moves")
    }

    /// R1 and R2 are added to every phase's pool, so they must resolve too
    /// even though no move cites them.
    func testTheTwoBaselineReadingsResolve() throws {
        let content = try loadedContent()
        let map = try map(content)
        for tag in ["R1", "R2"] {
            XCTAssertNotNil(
                CycleMapLinks.reading(forTag: tag, map: map, content: content),
                "\(tag) underpins every phase's practice pool and must resolve"
            )
        }
    }

    /// `frameworks_static` and the per-phase framework keys use different
    /// names and line up by position. If that pairing ever slips, a framework
    /// renders another's numbers — which looks plausible and is wrong.
    ///
    /// Mutation: reorder `frameworkKeyOrder` and the bar-count assertions fail.
    func testEveryFrameworkProducesBarsInEveryPhase() throws {
        let map = try map(try loadedContent())
        XCTAssertEqual(CycleMap.frameworkKeyOrder.count, map.frameworksStatic.count)

        for phase in map.phases {
            for index in map.frameworksStatic.indices {
                let bars = map.bars(frameworkIndex: index, phase: phase)
                XCTAssertFalse(
                    bars.isEmpty,
                    "\(phase.name)/\(map.frameworksStatic[index].label): no bars"
                )
            }
            // Cash is a now/average pair; Singer-Terhaar is the three computed
            // components. Both are the shapes that are not a plain list.
            XCTAssertEqual(map.bars(frameworkIndex: 0, phase: phase).count, 2, "cash")
            XCTAssertEqual(map.bars(frameworkIndex: 4, phase: phase).count, 3, "singer_terhaar")
        }
    }

    /// Singer-Terhaar is computed in code rather than shipped, so the
    /// arithmetic is pinned: RF, then phi x rho x sigma x SR, then
    /// (1 - phi) x sigma x SR.
    func testSingerTerhaarMatchesTheApprovedArithmetic() throws {
        let map = try map(try loadedContent())
        let phase = try XCTUnwrap(map.phases.first { $0.name == "Late expansion" })
        let st = phase.frameworks.singerTerhaar
        let i = map.singerTerhaarInputs

        XCTAssertEqual(st.rf, 4.5, accuracy: 0.001)
        XCTAssertEqual(st.phi, 0.80, accuracy: 0.001)

        let bars = map.bars(frameworkIndex: 4, phase: phase)
        XCTAssertEqual(bars[0].value, 4.5, accuracy: 0.001, "RF is the phase's own rf")
        XCTAssertEqual(bars[1].value, 0.80 * i.rho * i.sigma * i.sharpeGIM, accuracy: 0.001)
        XCTAssertEqual(bars[2].value, (1 - 0.80) * i.sigma * i.sharpeGIM, accuracy: 0.001)
        // 4.5 + 4.68 + 1.56
        XCTAssertEqual(bars.reduce(0) { $0 + $1.value }, 10.74, accuracy: 0.01)
    }

    /// The content pipeline forbids em dashes in user-facing strings, and the
    /// shipped file complies. This is what keeps a later JSON replacement from
    /// quietly reintroducing them.
    func testNoEmDashesInAnyUserFacingString() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "cycle_map", withExtension: "json")
                                ?? Bundle.main.url(forResource: "cycle_map", withExtension: "json"))
        let raw = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(raw.contains("\u{2014}"), "cycle_map.json reintroduced an em dash")
    }
}
