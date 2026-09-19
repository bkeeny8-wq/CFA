import SwiftUI
import PDFKit

/// MM Review: the MarkMeldrum.com condensed notes, indexed book → module →
/// page. Deliberately mirrors the Notes tab's book list so the two feel like
/// two views of the same curriculum rather than two different apps.
///
/// Unlike every other tab, this one's content can legitimately be ABSENT: the
/// PDFs are gitignored third-party coursework (see MMReviewBook.swift). A
/// missing file is an explanation, never an error.
struct MMReviewView: View {
    @Environment(ContentLoader.self) private var content
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if let bundle = content.mmReview {
                library(bundle)
            } else if let error = content.loadError {
                ContentUnavailableView(
                    "Content failed to load",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else {
                ContentUnavailableView(
                    "MM Review not configured",
                    systemImage: "doc.richtext",
                    description: Text("mm_review.json is missing from the app bundle.")
                )
            }
        }
        .background(Theme.paper)
        .toolbar(.hidden, for: .navigationBar)
        .navigationTitle("MM Review")
    }

    private func library(_ bundle: MMReviewBundle) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("MM Review")
                        .font(Theme.serif(.largeTitle, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .accessibilityIdentifier("mmreview.library")
                    Text("Book → learning module → the page it starts on.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.dust)
                }

                MMReviewBookList(bundle: bundle)
            }
            .padding(24)
        }
        .frame(maxWidth: horizontalSizeClass == .regular ? 640 : .infinity)
        .frame(maxWidth: .infinity)
    }
}

/// Owns expand state so toggling one book does not rebuild the others.
private struct MMReviewBookList: View {
    let bundle: MMReviewBundle
    @State private var expandedBookIDs: Set<String> = []

    private var missingCount: Int {
        bundle.books.filter { !MMPDFStore.isAvailable($0) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if missingCount == bundle.books.count {
                allMissingNotice
            }

            ParchmentGroup(title: "Books") {
                ForEach(bundle.books) { book in
                    let available = MMPDFStore.isAvailable(book)
                    BookDisclosureSection(
                        title: ProgressDisplay.shortName(book.areaID, fallback: book.name),
                        subtitle: available
                            ? "\(book.modules.count) modules · \(book.pageCount) pages"
                            : "PDF not installed",
                        accessibilityID: "mmreview.book.\(book.areaID)",
                        isExpanded: $expandedBookIDs[book.areaID]
                    ) {
                        if available {
                            modules(book)
                        } else {
                            missingRow(book)
                        }
                    }
                }
            }
        }
    }

    private func modules(_ book: MMReviewBook) -> some View {
        VStack(spacing: 0) {
            ForEach(book.modules) { module in
                NavigationLink {
                    MMModuleReaderView(book: book, module: module)
                } label: {
                    BookChildRow(
                        title: module.title,
                        subtitle: "\(module.pageCount) page\(module.pageCount == 1 ? "" : "s")",
                        trailing: "p\(module.startPage)"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mmreview.module.\(book.areaID).\(module.startPage)")
            }
        }
    }

    private func missingRow(_ book: MMReviewBook) -> some View {
        Text("Add \(book.fileName) to CFAL3/Resources/MMReview/ and rebuild.")
            .font(.footnote)
            .foregroundStyle(Theme.dust)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 8)
    }

    private var allMissingNotice: some View {
        ParchmentGroup {
            VStack(alignment: .leading, spacing: 8) {
                Label("No PDFs installed", systemImage: "doc.questionmark")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text("""
                    The MM Review PDFs are not committed to this repository — \
                    they are purchased coursework. Copy the six files into \
                    CFAL3/Resources/MMReview/ and rebuild; the module index \
                    below is already in place.
                    """)
                    .font(.footnote)
                    .foregroundStyle(Theme.dust)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("mmreview.missing")
    }
}

/// One module, opened at the page its learning outcomes start on. The whole
/// book stays scrollable from there — module boundaries are a starting point,
/// not a wall, because Meldrum's review sections refer back across them.
struct MMModuleReaderView: View {
    let book: MMReviewBook
    let module: MMReviewModule

    @State private var currentPage: Int
    @State private var document: PDFDocumentBox?

    init(book: MMReviewBook, module: MMReviewModule) {
        self.book = book
        self.module = module
        _currentPage = State(initialValue: module.startPage)
    }

    var body: some View {
        Group {
            if let document {
                MMPDFReader(
                    document: document.document,
                    startPage: module.startPage,
                    currentPage: $currentPage
                )
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .bottom) { pageBar }
            } else {
                ContentUnavailableView(
                    "PDF not installed",
                    systemImage: "doc.questionmark",
                    description: Text("Add \(book.fileName) to CFAL3/Resources/MMReview/ and rebuild.")
                )
            }
        }
        .navigationTitle(module.title)
        .navigationBarTitleDisplayMode(.inline)
        .background(Theme.paper)
        .task {
            // Off the main thread: parsing a 126-page encrypted PDF on the
            // main actor stalls the push animation.
            if document == nil {
                let loaded = await Task.detached(priority: .userInitiated) {
                    MMPDFStore.document(for: book).map(PDFDocumentBox.init)
                }.value
                document = loaded
            }
        }
    }

    private var pageBar: some View {
        Text(pageLabel)
            .font(.caption.weight(.medium))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Theme.cardFill, in: Capsule())
            .padding(.bottom, 14)
            .accessibilityIdentifier("mmreview.pagebar")
            .accessibilityLabel(pageLabel)
    }

    private var pageLabel: String {
        let inModule = currentPage >= module.startPage && currentPage <= module.endPage
        return inModule
            ? "Page \(currentPage) of \(book.pageCount) · \(module.title)"
            : "Page \(currentPage) of \(book.pageCount) · outside this module"
    }
}

/// PDFDocument is a reference type that is not Sendable; boxing it keeps the
/// detached load explicit about what crosses the boundary.
struct PDFDocumentBox: @unchecked Sendable {
    let document: PDFDocument
    init(_ document: PDFDocument) { self.document = document }
}
