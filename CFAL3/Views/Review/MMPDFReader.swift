import SwiftUI
import PDFKit

/// A PDFKit page view over one of the MM Review books.
///
/// The PDFs are ENCRYPTED but not password-locked, which PDFKit opens without
/// complaint — `isEncrypted` is true and `isLocked` is false for all six. Do
/// not "fix" that by stripping encryption; the files are third-party
/// coursework and are meant to stay exactly as purchased.
struct MMPDFReader: UIViewRepresentable {
    let document: PDFDocument
    /// 1-based, matching the PDF's own printed table of contents.
    let startPage: Int
    @Binding var currentPage: Int

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.autoScales = true
        view.backgroundColor = UIColor(Theme.paper)
        view.delegate = context.coordinator

        // `go(to:)` is a NO-OP until PDFKit has laid the document out — calling
        // it here leaves the reader sitting on page 1, which is what shipped
        // the first time. Deferring one runloop turn gives the scroll view its
        // size, and the coordinator flag stops `updateUIView` from yanking the
        // reader back to the module every time SwiftUI re-runs the body.
        context.coordinator.jump = { [weak view] in
            guard let view, let page = document.page(at: max(0, startPage - 1)) else { return }
            view.go(to: page)
        }
        DispatchQueue.main.async { context.coordinator.jumpOnce() }

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: view
        )
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        context.coordinator.onPageChange = { page in
            // The notification fires during PDFKit's own layout, so publishing
            // straight into @State here would mutate view state mid-update.
            DispatchQueue.main.async {
                if currentPage != page { currentPage = page }
            }
        }
        if view.document !== document {
            view.document = document
            context.coordinator.hasJumped = false
            DispatchQueue.main.async { context.coordinator.jumpOnce() }
        }
    }

    static func dismantleUIView(_ view: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, PDFViewDelegate {
        var onPageChange: ((Int) -> Void)?
        var jump: (() -> Void)?
        var hasJumped = false

        /// Opening the module is a one-time move. Re-running it on every
        /// `updateUIView` would drag the reader back to `startPage` each time
        /// the page counter published a new value — an unusable reader that
        /// snaps back the moment you scroll.
        func jumpOnce() {
            guard !hasJumped else { return }
            hasJumped = true
            jump?()
        }

        @objc func pageChanged(_ note: Notification) {
            guard let view = note.object as? PDFView,
                  let page = view.currentPage,
                  let document = view.document
            else { return }
            onPageChange?(document.index(for: page) + 1)
        }
    }
}

/// Loads a book's PDF from the app bundle.
///
/// Returns nil when the file is absent, which is the normal state of a clone —
/// the PDFs are gitignored. Callers must render an explanation, never an error.
enum MMPDFStore {
    static func url(for book: MMReviewBook) -> URL? {
        let name = (book.fileName as NSString).deletingPathExtension
        // Folder reference, so the files land under MMReview/ in the bundle.
        return Bundle.main.url(forResource: name, withExtension: "pdf", subdirectory: "MMReview")
            ?? Bundle.main.url(forResource: name, withExtension: "pdf")
    }

    static func document(for book: MMReviewBook) -> PDFDocument? {
        guard let url = url(for: book) else { return nil }
        return PDFDocument(url: url)
    }

    static func isAvailable(_ book: MMReviewBook) -> Bool {
        url(for: book) != nil
    }
}
