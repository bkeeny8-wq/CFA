import Foundation

/// The MarkMeldrum.com condensed notes, presented as a book → module → page
/// index over PDFs that ship **outside** version control.
///
/// `mm_review.json` is tracked and holds only module titles and page numbers —
/// factual metadata. The PDFs themselves live in `CFAL3/Resources/MMReview/`,
/// which is gitignored: they are purchased third-party coursework, encrypted
/// and stamped with a per-purchaser watermark, and this repository is public.
/// Everything here therefore has to behave correctly when the PDFs are simply
/// absent — that is the normal state of a fresh clone, not an error.
struct MMReviewBundle: Decodable {
    let version: Int
    let source: String
    let books: [MMReviewBook]
}

struct MMReviewBook: Decodable, Identifiable {
    /// Matches a `CurriculumArea.id` in los_master, so a book lines up with the
    /// same six books the rest of the app shows.
    let areaID: String
    let name: String
    let fileName: String
    let pageCount: Int
    let modules: [MMReviewModule]

    var id: String { areaID }

    /// Modules that map onto a curriculum reading. The "Review" sections at the
    /// end of four of the books do not, and are deliberately kept in `modules`
    /// so they remain reachable.
    var readingModules: [MMReviewModule] {
        modules.filter { $0.readingID != nil }
    }
}

struct MMReviewModule: Decodable, Identifiable, Equatable {
    let title: String
    /// 1-based, as printed in the PDF's own table of contents. Every value was
    /// verified against the rendered page; `startPage` lands on the module's
    /// learning-outcome title page.
    let startPage: Int
    let endPage: Int
    /// Absent for the four "Review" sections, and for anything Meldrum covers
    /// only on video (`Application of the Code and Standards` has no pages).
    let readingID: String?

    var id: String { "\(title)-\(startPage)" }

    var pageCount: Int { max(0, endPage - startPage + 1) }
}

extension MMReviewBundle {
    func book(forArea areaID: String) -> MMReviewBook? {
        books.first { $0.areaID == areaID }
    }

    /// The module covering a reading, with the book it belongs to — used to
    /// offer "open this reading in MM Review" from the reading itself.
    func module(forReading readingID: String) -> (book: MMReviewBook, module: MMReviewModule)? {
        for book in books {
            if let module = book.modules.first(where: { $0.readingID == readingID }) {
                return (book, module)
            }
        }
        return nil
    }
}
