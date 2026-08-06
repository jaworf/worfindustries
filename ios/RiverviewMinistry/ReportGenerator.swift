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
    private static let margin: CGFloat = 48
    private static let headerHeight: CGFloat = 94
    private static let footerHeight: CGFloat = 24
    private static let rowHeight: CGFloat = 31
    private static let roleHeaderHeight: CGFloat = 27
    private static let noteBlockHeight: CGFloat = 36
    private static let riverBlue = CGColor(
        red: 31.0 / 255.0,
        green: 95.0 / 255.0,
        blue: 139.0 / 255.0,
        alpha: 1
    )
    private static let riverBlueDark = CGColor(
        red: 18.0 / 255.0,
        green: 62.0 / 255.0,
        blue: 95.0 / 255.0,
        alpha: 1
    )
    private static let riverBlueSoft = CGColor(
        red: 232.0 / 255.0,
        green: 242.0 / 255.0,
        blue: 248.0 / 255.0,
        alpha: 1
    )
    private static let flatColumns: [(title: String, width: CGFloat)] = [
        ("Ministry", 210),
        ("Volunteer", 170),
        ("Position", 120),
        ("Term End", 100),
        ("Voted", 96)
    ]
    private static let groupedColumns: [(title: String, width: CGFloat)] = [
        ("Volunteer", 260),
        ("Position", 150),
        ("Term End", 145),
        ("Voted", 141)
    ]

    static func makePDF(
        assignments: [AssignmentDetail],
        filterDescription: String,
        groupByRole: Bool = false
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
        if groupByRole {
            drawGroupedPages(
                context,
                assignments: sorted,
                filterDescription: filterDescription
            )
        } else {
            drawFlatPages(
                context,
                assignments: sorted,
                filterDescription: filterDescription
            )
        }

        context.closePDF()
        return output as Data
    }

    private static func drawFlatPages(
        _ context: CGContext,
        assignments: [AssignmentDetail],
        filterDescription: String
    ) {
        let pages = paginateFlat(assignments)
        let pageCount = pages.count

        for (pageIndex, pageAssignments) in pages.enumerated() {
            context.beginPDFPage(nil)
            drawPageHeader(
                context,
                filterDescription: filterDescription,
                totalRows: assignments.count
            )
            drawColumnHeaders(context, columns: flatColumns)

            if pageAssignments.isEmpty {
                drawEmptyMessage(context)
            } else {
                var cursorY = pageSize.height - margin - headerHeight - rowHeight
                for (localIndex, assignment) in pageAssignments.enumerated() {
                    cursorY -= rowHeight
                    drawFlatRow(
                        context,
                        assignment: assignment,
                        index: localIndex,
                        y: cursorY
                    )
                    if let note = assignment.publishedNote {
                        cursorY -= noteBlockHeight
                        drawNoteBlock(
                            context,
                            note: note,
                            width: flatColumns.reduce(0) { $0 + $1.width },
                            y: cursorY
                        )
                    }
                }
            }
            drawPageFooter(
                context,
                pageNumber: pageIndex + 1,
                pageCount: pageCount
            )
            context.endPDFPage()
        }
    }

    private static func paginateFlat(
        _ assignments: [AssignmentDetail]
    ) -> [[AssignmentDetail]] {
        guard !assignments.isEmpty else { return [[]] }

        let availableHeight = pageSize.height
            - margin * 2
            - headerHeight
            - rowHeight
            - footerHeight
        var pages: [[AssignmentDetail]] = [[]]
        var remainingHeight = availableHeight

        for assignment in assignments {
            let height = assignmentHeight(assignment)
            if !pages[pages.count - 1].isEmpty, remainingHeight < height {
                pages.append([])
                remainingHeight = availableHeight
            }
            pages[pages.count - 1].append(assignment)
            remainingHeight -= height
        }
        return pages
    }

    private static func drawGroupedPages(
        _ context: CGContext,
        assignments: [AssignmentDetail],
        filterDescription: String
    ) {
        let pages = paginateGrouped(assignments)
        let pageCount = pages.count

        for (pageIndex, items) in pages.enumerated() {
            context.beginPDFPage(nil)
            drawPageHeader(
                context,
                filterDescription: filterDescription,
                totalRows: assignments.count
            )
            drawColumnHeaders(context, columns: groupedColumns)

            if assignments.isEmpty {
                drawEmptyMessage(context)
            } else {
                drawGroupedItems(context, items: items)
            }
            drawPageFooter(
                context,
                pageNumber: pageIndex + 1,
                pageCount: pageCount
            )
            context.endPDFPage()
        }
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
        totalRows: Int
    ) {
        let bannerHeight: CGFloat = 64
        let bannerY = pageSize.height - margin - bannerHeight
        context.setFillColor(riverBlue)
        context.fill(
            CGRect(
                x: margin,
                y: bannerY,
                width: pageSize.width - margin * 2,
                height: bannerHeight
            )
        )
        drawText(
            context,
            "Pasco Riverview Adventist Church",
            in: CGRect(
                x: margin + 16,
                y: bannerY + 35,
                width: pageSize.width - margin * 2 - 32,
                height: 24
            ),
            fontSize: 18,
            color: CGColor(gray: 1, alpha: 1),
            bold: true
        )
        drawText(
            context,
            "Volunteer Ministry Directory",
            in: CGRect(
                x: margin + 16,
                y: bannerY + 16,
                width: pageSize.width - margin * 2 - 32,
                height: 18
            ),
            fontSize: 11,
            color: CGColor(red: 0.86, green: 0.94, blue: 0.98, alpha: 1)
        )
        drawText(
            context,
            "\(filterDescription)  -  \(totalRows) assignment\(totalRows == 1 ? "" : "s")",
            in: CGRect(
                x: margin,
                y: bannerY - 21,
                width: pageSize.width - margin * 2,
                height: 14
            ),
            fontSize: 8,
            color: CGColor(gray: 0.35, alpha: 1)
        )
    }

    private static func drawPageFooter(
        _ context: CGContext,
        pageNumber: Int,
        pageCount: Int
    ) {
        let ruleY = margin - 4
        context.setStrokeColor(CGColor(gray: 0.82, alpha: 1))
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: margin, y: ruleY))
        context.addLine(to: CGPoint(x: pageSize.width - margin, y: ruleY))
        context.strokePath()

        drawText(
            context,
            "\(pageNumber) of \(pageCount)",
            in: CGRect(
                x: margin,
                y: margin - 25,
                width: pageSize.width - margin * 2,
                height: 14
            ),
            fontSize: 8,
            color: CGColor(gray: 0.38, alpha: 1),
            alignment: .right
        )
    }

    private static func drawColumnHeaders(
        _ context: CGContext,
        columns: [(title: String, width: CGFloat)]
    ) {
        var x = margin
        let y = pageSize.height - margin - headerHeight - rowHeight
        context.setFillColor(riverBlueSoft)
        context.fill(
            CGRect(x: margin, y: y, width: columns.reduce(0) { $0 + $1.width }, height: rowHeight)
        )
        for column in columns {
            drawText(
                context,
                column.title.uppercased(),
                in: CGRect(x: x + 6, y: y + 9, width: column.width - 12, height: 13),
                fontSize: 8,
                color: riverBlueDark,
                bold: true
            )
            x += column.width
        }
    }

    private static func drawFlatRow(
        _ context: CGContext,
        assignment: AssignmentDetail,
        index: Int,
        y: CGFloat
    ) {
        if index.isMultiple(of: 2) {
            context.setFillColor(CGColor(gray: 0.975, alpha: 1))
            context.fill(
                CGRect(
                    x: margin,
                    y: y,
                    width: flatColumns.reduce(0) { $0 + $1.width },
                    height: rowHeight
                )
            )
        }
        context.setStrokeColor(CGColor(gray: 0.86, alpha: 1))
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: margin, y: y))
        context.addLine(
            to: CGPoint(x: margin + flatColumns.reduce(0) { $0 + $1.width }, y: y)
        )
        context.strokePath()

        let values = [
            assignment.roleName,
            assignment.personName,
            assignment.subRoleName ?? "Volunteer",
            assignment.endDate.flatMap(AppDate.parse).map(AppDate.display) ?? "—",
            assignment.voteDate.flatMap(AppDate.parse).map(AppDate.display) ?? "—"
        ]
        var x = margin
        for (column, value) in zip(flatColumns, values) {
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

    private static func paginateGrouped(
        _ assignments: [AssignmentDetail]
    ) -> [[GroupedItem]] {
        guard !assignments.isEmpty else { return [[]] }

        let availableHeight = pageSize.height
            - margin * 2
            - headerHeight
            - rowHeight
            - footerHeight
        let groups = Dictionary(grouping: assignments, by: \.roleName)
            .map { roleName, assignments in
                (
                    roleName,
                    assignments.sorted(by: reportOrder)
                )
            }
            .sorted {
                $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending
            }

        var pages: [[GroupedItem]] = [[]]
        var remainingHeight = availableHeight

        for (roleName, roleAssignments) in groups {
            let completeGroupHeight = roleHeaderHeight + roleAssignments.reduce(0) {
                $0 + assignmentHeight($1)
            }
            if
                !pages[pages.count - 1].isEmpty,
                completeGroupHeight <= availableHeight,
                remainingHeight < completeGroupHeight
            {
                pages.append([])
                remainingHeight = availableHeight
            }

            var assignmentIndex = 0
            var continued = false

            while assignmentIndex < roleAssignments.count {
                let nextHeight = assignmentHeight(roleAssignments[assignmentIndex])
                if remainingHeight < roleHeaderHeight + nextHeight {
                    pages.append([])
                    remainingHeight = availableHeight
                }

                pages[pages.count - 1].append(
                    .roleHeader(roleName, continued: continued)
                )
                remainingHeight -= roleHeaderHeight

                while
                    assignmentIndex < roleAssignments.count,
                    remainingHeight >= assignmentHeight(roleAssignments[assignmentIndex])
                {
                    let assignment = roleAssignments[assignmentIndex]
                    pages[pages.count - 1].append(
                        .assignment(assignment)
                    )
                    assignmentIndex += 1
                    remainingHeight -= assignmentHeight(assignment)
                }

                if assignmentIndex < roleAssignments.count {
                    pages.append([])
                    remainingHeight = availableHeight
                    continued = true
                }
            }
        }

        return pages
    }

    private static func drawGroupedItems(
        _ context: CGContext,
        items: [GroupedItem]
    ) {
        var cursorY = pageSize.height - margin - headerHeight - rowHeight
        var rowIndex = 0

        for item in items {
            switch item {
            case let .roleHeader(roleName, continued):
                cursorY -= roleHeaderHeight
                drawRoleHeader(
                    context,
                    roleName: roleName,
                    continued: continued,
                    y: cursorY
                )
            case let .assignment(assignment):
                cursorY -= rowHeight
                drawGroupedRow(
                    context,
                    assignment: assignment,
                    index: rowIndex,
                    y: cursorY
                )
                if let note = assignment.publishedNote {
                    cursorY -= noteBlockHeight
                    drawNoteBlock(
                        context,
                        note: note,
                        width: groupedColumns.reduce(0) { $0 + $1.width },
                        y: cursorY
                    )
                }
                rowIndex += 1
            }
        }
    }

    private static func drawRoleHeader(
        _ context: CGContext,
        roleName: String,
        continued: Bool,
        y: CGFloat
    ) {
        let tableWidth = groupedColumns.reduce(0) { $0 + $1.width }
        context.setFillColor(riverBlue)
        context.fill(
            CGRect(
                x: margin,
                y: y,
                width: tableWidth,
                height: roleHeaderHeight
            )
        )
        drawText(
            context,
            continued ? "\(roleName) (continued)" : roleName,
            in: CGRect(
                x: margin + 8,
                y: y + 8,
                width: tableWidth - 16,
                height: 15
            ),
            fontSize: 10.5,
            color: CGColor(gray: 1, alpha: 1),
            bold: true
        )
    }

    private static func drawGroupedRow(
        _ context: CGContext,
        assignment: AssignmentDetail,
        index: Int,
        y: CGFloat
    ) {
        let tableWidth = groupedColumns.reduce(0) { $0 + $1.width }
        if index.isMultiple(of: 2) {
            context.setFillColor(CGColor(gray: 0.975, alpha: 1))
            context.fill(
                CGRect(
                    x: margin,
                    y: y,
                    width: tableWidth,
                    height: rowHeight
                )
            )
        }
        context.setStrokeColor(CGColor(gray: 0.86, alpha: 1))
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: margin, y: y))
        context.addLine(
            to: CGPoint(x: margin + tableWidth, y: y)
        )
        context.strokePath()

        let values = [
            assignment.personName,
            assignment.subRoleName ?? "Volunteer",
            assignment.endDate.flatMap(AppDate.parse).map(AppDate.display) ?? "—",
            assignment.voteDate.flatMap(AppDate.parse).map(AppDate.display) ?? "—"
        ]
        var x = margin
        for (column, value) in zip(groupedColumns, values) {
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

    private static func assignmentHeight(_ assignment: AssignmentDetail) -> CGFloat {
        rowHeight + (assignment.publishedNote == nil ? 0 : noteBlockHeight)
    }

    private static func drawNoteBlock(
        _ context: CGContext,
        note: String,
        width: CGFloat,
        y: CGFloat
    ) {
        context.setFillColor(riverBlueSoft)
        context.fill(
            CGRect(x: margin, y: y, width: width, height: noteBlockHeight)
        )
        context.setFillColor(riverBlue)
        context.fill(
            CGRect(x: margin, y: y, width: 3, height: noteBlockHeight)
        )
        drawText(
            context,
            "NOTE",
            in: CGRect(x: margin + 9, y: y + 14, width: 34, height: 12),
            fontSize: 7,
            color: riverBlueDark,
            bold: true
        )
        drawWrappedText(
            context,
            note,
            in: CGRect(
                x: margin + 47,
                y: y + 6,
                width: width - 57,
                height: noteBlockHeight - 11
            ),
            fontSize: 7.7,
            color: riverBlueDark
        )
    }

    private static func drawEmptyMessage(_ context: CGContext) {
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

    private static func drawWrappedText(
        _ context: CGContext,
        _ text: String,
        in rect: CGRect,
        fontSize: CGFloat,
        color: CGColor
    ) {
        let safeText = text
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: "–", with: "-")
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.lineSpacing = 1
        let attributed = NSAttributedString(
            string: safeText,
            attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String):
                    CTFontCreateWithName("Helvetica" as CFString, fontSize, nil),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
                .paragraphStyle: paragraph
            ]
        )
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGMutablePath()
        path.addRect(rect)
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: 0),
            path,
            nil
        )
        CTFrameDraw(frame, context)
    }

    private enum GroupedItem {
        case roleHeader(String, continued: Bool)
        case assignment(AssignmentDetail)
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
