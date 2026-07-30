import CoreGraphics
import CoreText
import Foundation
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum ReportGenerator {
    private static let pageSize = CGSize(width: 792, height: 612)
    private static let margin: CGFloat = 36
    private static let headerHeight: CGFloat = 82
    private static let rowHeight: CGFloat = 31
    private static let columns: [(title: String, width: CGFloat)] = [
        ("Ministry", 190),
        ("Volunteer", 145),
        ("Position", 95),
        ("Term", 150),
        ("Ends", 70),
        ("Voted", 70)
    ]

    static func makePDF(
        assignments: [AssignmentDetail],
        filterDescription: String
    ) throws -> Data {
        let output = NSMutableData()
        guard
            let consumer = CGDataConsumer(data: output as CFMutableData),
            var mediaBox = Optional(
                CGRect(origin: .zero, size: pageSize)
            ),
            let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else {
            throw ReportError.couldNotCreatePDF
        }

        let sorted = assignments.sorted(by: reportOrder)
        let availableHeight = pageSize.height - margin * 2 - headerHeight - rowHeight
        let rowsPerPage = max(1, Int(availableHeight / rowHeight))
        let pageCount = max(1, Int(ceil(Double(sorted.count) / Double(rowsPerPage))))

        for pageIndex in 0..<pageCount {
            context.beginPDFPage(nil)
            drawPageHeader(
                context,
                filterDescription: filterDescription,
                pageNumber: pageIndex + 1,
                pageCount: pageCount,
                totalRows: sorted.count
            )
            drawColumnHeaders(context)

            let start = pageIndex * rowsPerPage
            let end = min(start + rowsPerPage, sorted.count)
            if start < end {
                for (localIndex, assignment) in sorted[start..<end].enumerated() {
                    drawRow(context, assignment: assignment, index: localIndex)
                }
            } else {
                drawText(
                    context,
                    "No assignments match the selected filters.",
                    in: CGRect(
                        x: margin,
                        y: pageSize.height - margin - headerHeight - rowHeight - 42,
                        width: pageSize.width - margin * 2,
                        height: 30
                    ),
                    fontSize: 11,
                    color: CGColor(gray: 0.3, alpha: 1)
                )
            }
            context.endPDFPage()
        }

        context.closePDF()
        return output as Data
    }

    private static func reportOrder(
        _ left: AssignmentDetail,
        _ right: AssignmentDetail
    ) -> Bool {
        if left.roleName.localizedCaseInsensitiveCompare(right.roleName) != .orderedSame {
            return left.roleName.localizedCaseInsensitiveCompare(right.roleName) == .orderedAscending
        }
        if left.leadershipRank != right.leadershipRank {
            return left.leadershipRank < right.leadershipRank
        }
        if left.lastName.localizedCaseInsensitiveCompare(right.lastName) != .orderedSame {
            return left.lastName.localizedCaseInsensitiveCompare(right.lastName) == .orderedAscending
        }
        return left.firstName.localizedCaseInsensitiveCompare(right.firstName) == .orderedAscending
    }

    private static func drawPageHeader(
        _ context: CGContext,
        filterDescription: String,
        pageNumber: Int,
        pageCount: Int,
        totalRows: Int
    ) {
        context.setFillColor(CGColor(red: 0.05, green: 0.22, blue: 0.18, alpha: 1))
        context.fill(
            CGRect(x: 0, y: pageSize.height - 98, width: pageSize.width, height: 98)
        )
        drawText(
            context,
            "Pasco Riverview Adventist Church",
            in: CGRect(x: margin, y: pageSize.height - 57, width: 500, height: 24),
            fontSize: 18,
            color: CGColor(gray: 1, alpha: 1),
            bold: true
        )
        drawText(
            context,
            "Volunteer Ministry Directory",
            in: CGRect(x: margin, y: pageSize.height - 80, width: 500, height: 18),
            fontSize: 11,
            color: CGColor(red: 0.82, green: 0.92, blue: 0.87, alpha: 1)
        )
        drawText(
            context,
            "Page \(pageNumber) of \(pageCount)",
            in: CGRect(x: pageSize.width - 150, y: pageSize.height - 58, width: 114, height: 18),
            fontSize: 9,
            color: CGColor(gray: 1, alpha: 1),
            alignment: .right
        )
        drawText(
            context,
            "\(filterDescription)  •  \(totalRows) assignment\(totalRows == 1 ? "" : "s")",
            in: CGRect(x: margin, y: pageSize.height - 116, width: pageSize.width - margin * 2, height: 14),
            fontSize: 8,
            color: CGColor(gray: 0.35, alpha: 1)
        )
    }

    private static func drawColumnHeaders(_ context: CGContext) {
        var x = margin
        let y = pageSize.height - margin - headerHeight - rowHeight
        context.setFillColor(CGColor(red: 0.91, green: 0.94, blue: 0.92, alpha: 1))
        context.fill(
            CGRect(x: margin, y: y, width: columns.reduce(0) { $0 + $1.width }, height: rowHeight)
        )
        for column in columns {
            drawText(
                context,
                column.title.uppercased(),
                in: CGRect(x: x + 6, y: y + 9, width: column.width - 12, height: 13),
                fontSize: 8,
                color: CGColor(red: 0.05, green: 0.22, blue: 0.18, alpha: 1),
                bold: true
            )
            x += column.width
        }
    }

    private static func drawRow(
        _ context: CGContext,
        assignment: AssignmentDetail,
        index: Int
    ) {
        let tableTop = pageSize.height - margin - headerHeight - rowHeight
        let y = tableTop - CGFloat(index + 1) * rowHeight
        if index.isMultiple(of: 2) {
            context.setFillColor(CGColor(gray: 0.975, alpha: 1))
            context.fill(
                CGRect(
                    x: margin,
                    y: y,
                    width: columns.reduce(0) { $0 + $1.width },
                    height: rowHeight
                )
            )
        }
        context.setStrokeColor(CGColor(gray: 0.86, alpha: 1))
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: margin, y: y))
        context.addLine(
            to: CGPoint(x: margin + columns.reduce(0) { $0 + $1.width }, y: y)
        )
        context.strokePath()

        let values = [
            assignment.roleName,
            assignment.personName,
            assignment.subRoleName ?? "Volunteer",
            assignment.termName ?? "No term",
            assignment.endDate.flatMap(AppDate.parse).map(AppDate.display) ?? "—",
            assignment.voteDate.flatMap(AppDate.parse).map(AppDate.display) ?? "—"
        ]
        var x = margin
        for (column, value) in zip(columns, values) {
            drawText(
                context,
                value,
                in: CGRect(x: x + 6, y: y + 8, width: column.width - 12, height: 16),
                fontSize: 8.5,
                color: CGColor(gray: 0.12, alpha: 1)
            )
            x += column.width
        }
    }

    private static func drawText(
        _ context: CGContext,
        _ text: String,
        in rect: CGRect,
        fontSize: CGFloat,
        color: CGColor,
        bold: Bool = false,
        alignment: CTTextAlignment = .left
    ) {
        let safeText = text
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
        let fontName = bold ? "Helvetica-Bold" : "Helvetica"
        let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
        ]
        let attributed = NSAttributedString(string: safeText, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributed)
        let truncated = CTLineCreateTruncatedLine(
            line,
            Double(rect.width),
            .end,
            CTLineCreateWithAttributedString(
                NSAttributedString(string: "…", attributes: attributes)
            )
        ) ?? line

        let lineWidth = CGFloat(CTLineGetTypographicBounds(truncated, nil, nil, nil))
        let x = alignment == .right ? max(rect.minX, rect.maxX - lineWidth) : rect.minX
        context.textPosition = CGPoint(x: x, y: rect.minY)
        CTLineDraw(truncated, context)
    }
}

enum ReportError: LocalizedError {
    case couldNotCreatePDF

    var errorDescription: String? {
        "The PDF report could not be created."
    }
}

struct PDFReportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

#if os(iOS)
struct PDFPreview: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        view.document = PDFDocument(data: data)
    }
}
#elseif os(macOS)
struct PDFPreview: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        view.document = PDFDocument(data: data)
    }
}
#endif
