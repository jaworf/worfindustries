import PDFKit
import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct AssignmentFilter: Sendable {
    var search = ""
    var roleId: UUID?
    var endingWindow: EndingWindow = .all

    func apply(
        to assignments: [AssignmentDetail],
        now: Date = Date()
    ) -> [AssignmentDetail] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: now)
        let windowEnd = endingWindow.monthCount.flatMap {
            calendar.date(byAdding: .month, value: $0, to: today)
        }

        return assignments
            .filter { assignment in
                guard assignment.status == "active" else { return false }
                if let roleId, assignment.roleId != roleId { return false }
                if !query.isEmpty {
                    let values = [
                        assignment.personName,
                        assignment.roleName,
                        assignment.subRoleName ?? "",
                        assignment.termName ?? ""
                    ]
                    guard values.contains(where: {
                        $0.localizedCaseInsensitiveContains(query)
                    }) else {
                        return false
                    }
                }
                if let windowEnd {
                    guard
                        let endDate = assignment.endDateValue,
                        endDate >= today,
                        endDate <= windowEnd
                    else {
                        return false
                    }
                }
                return true
            }
            .sorted(by: AssignmentFilter.reportOrder)
    }

    func description(roles: [MinistryRole]) -> String {
        var parts: [String] = []
        if let roleId, let role = roles.first(where: { $0.id == roleId }) {
            parts.append("Role: \(role.name)")
        }
        if let query = search.nilIfBlank {
            parts.append("Search: \(query)")
        }
        if endingWindow != .all {
            parts.append(endingWindow.rawValue)
        }
        return parts.isEmpty ? "All active assignments" : parts.joined(separator: " • ")
    }

    private static func reportOrder(
        _ left: AssignmentDetail,
        _ right: AssignmentDetail
    ) -> Bool {
        let roleOrder = left.roleName.localizedCaseInsensitiveCompare(right.roleName)
        if roleOrder != .orderedSame { return roleOrder == .orderedAscending }
        if left.leadershipRank != right.leadershipRank {
            return left.leadershipRank < right.leadershipRank
        }
        let lastOrder = left.lastName.localizedCaseInsensitiveCompare(right.lastName)
        if lastOrder != .orderedSame { return lastOrder == .orderedAscending }
        return left.firstName.localizedCaseInsensitiveCompare(right.firstName)
            == .orderedAscending
    }
}

struct AssignmentFilterControls: View {
    @Binding var filter: AssignmentFilter
    let roles: [MinistryRole]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Search person, role, position, or term", text: $filter.search)
                .textFieldStyle(.roundedBorder)

            HStack {
                Picker("Role", selection: $filter.roleId) {
                    Text("All roles").tag(UUID?.none)
                    ForEach(roles.filter(\.isActive)) { role in
                        Text(role.name).tag(Optional(role.id))
                    }
                }
                Picker("Term ending", selection: $filter.endingWindow) {
                    ForEach(EndingWindow.allCases) { window in
                        Text(window.rawValue).tag(window)
                    }
                }
                if filter.roleId != nil || filter.search.nilIfBlank != nil
                    || filter.endingWindow != .all
                {
                    Button("Clear") {
                        filter = AssignmentFilter()
                    }
                }
            }
        }
    }
}

struct DirectoryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var filter = AssignmentFilter()

    private var filtered: [AssignmentDetail] {
        filter.apply(to: model.assignments)
    }

    private var grouped: [(String, [AssignmentDetail])] {
        Dictionary(grouping: filtered, by: \.roleName)
            .map { ($0.key, $0.value) }
            .sorted {
                $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            AssignmentFilterControls(filter: $filter, roles: model.roles)
                .padding()
                .background(.bar)

            if grouped.isEmpty {
                ContentUnavailableView(
                    "No matching assignments",
                    systemImage: "person.3",
                    description: Text("Try clearing one or more filters.")
                )
            } else {
                List {
                    ForEach(grouped, id: \.0) { roleName, assignments in
                        Section(roleName) {
                            ForEach(assignments) { assignment in
                                AssignmentDirectoryRow(assignment: assignment)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Volunteer Directory")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Text("\(filtered.count)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(filtered.count) assignments")
            }
        }
    }
}

private struct AssignmentDirectoryRow: View {
    let assignment: AssignmentDetail

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(assignment.personName)
                    .fontWeight(assignment.leadershipRank < 100 ? .semibold : .regular)
                HStack(spacing: 6) {
                    if let subRole = assignment.subRoleName {
                        Text(subRole)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(
                                assignment.leadershipRank < 100
                                    ? Color.accentColor.opacity(0.15)
                                    : Color.secondary.opacity(0.12),
                                in: Capsule()
                            )
                    }
                    Text(assignment.termName ?? "No term")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                if let end = assignment.endDateValue {
                    Text("Ends \(AppDate.display(end))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if assignment.voteMissing {
                    Label("Vote missing", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

struct ReportsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var filter = AssignmentFilter()
    @State private var pdfData: Data?
    @State private var showingPreview = false

    private var filtered: [AssignmentDetail] {
        filter.apply(to: model.assignments)
    }

    var body: some View {
        Form {
            Section("Report filters") {
                AssignmentFilterControls(filter: $filter, roles: model.roles)
            }

            Section {
                LabeledContent("Assignments included") {
                    Text("\(filtered.count)")
                        .monospacedDigit()
                }
                Text(filter.description(roles: model.roles))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button {
                    buildReport()
                } label: {
                    Label("Build PDF Report", systemImage: "doc.richtext")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } header: {
                Text("Preview")
            } footer: {
                Text(
                    "The PDF uses the same leadership-first ordering as the directory: " +
                    "Head/Lead, Co-Head/Co-Lead, Assistant Head, then last and first name."
                )
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Reports")
        .sheet(isPresented: $showingPreview) {
            if let pdfData {
                PDFReportPreview(data: pdfData)
            }
        }
    }

    private func buildReport() {
        do {
            pdfData = try ReportGenerator.makePDF(
                assignments: filtered,
                filterDescription: filter.description(roles: model.roles)
            )
            showingPreview = true
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}

private struct PDFReportPreview: View {
    @Environment(\.dismiss) private var dismiss
    let data: Data
    @State private var exporting = false

    var body: some View {
        NavigationStack {
            PDFPreview(data: data)
                .navigationTitle("Volunteer Directory PDF")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            printPDF(data)
                        } label: {
                            Label("Print", systemImage: "printer")
                        }
                        Button {
                            exporting = true
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                    }
                }
        }
        .frame(minWidth: 700, minHeight: 520)
        .fileExporter(
            isPresented: $exporting,
            document: PDFReportDocument(data: data),
            contentType: .pdf,
            defaultFilename: "Riverview-Volunteer-Directory"
        ) { _ in }
    }

    private func printPDF(_ data: Data) {
        #if os(iOS)
        let controller = UIPrintInteractionController.shared
        controller.printingItem = data
        controller.present(animated: true)
        #elseif os(macOS)
        guard let document = PDFDocument(data: data) else { return }
        let view = PDFView(
            frame: CGRect(origin: .zero, size: CGSize(width: 792, height: 612))
        )
        view.document = document
        NSPrintOperation(view: view).run()
        #endif
    }
}
