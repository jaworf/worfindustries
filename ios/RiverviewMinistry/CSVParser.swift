import Foundation

struct CSVDocument: Sendable {
    let headers: [String]
    let rows: [[String: String]]
}

enum CSVParserError: LocalizedError {
    case emptyFile
    case malformedRow(Int)

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            "The CSV file is empty."
        case .malformedRow(let row):
            "CSV row \(row) has more fields than the header row."
        }
    }
}

enum CSVParser {
    static func parse(data: Data) throws -> CSVDocument {
        guard var text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        text.removePrefix("\u{FEFF}")

        let matrix = parseRows(text)
        guard let first = matrix.first, !first.isEmpty else {
            throw CSVParserError.emptyFile
        }

        let headers = first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let rows: [[String: String]] = try matrix
            .dropFirst()
            .enumerated()
            .compactMap { entry -> [String: String]? in
            let (offset, values) = entry
            if values.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                return nil
            }
            guard values.count <= headers.count else {
                throw CSVParserError.malformedRow(offset + 2)
            }

            var record: [String: String] = [:]
            for (index, header) in headers.enumerated() {
                record[header] = index < values.count
                    ? values[index].trimmingCharacters(in: .whitespacesAndNewlines)
                    : ""
            }
            return record
        }

        return CSVDocument(headers: headers, rows: rows)
    }

    private static func parseRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            if character == "\"" {
                let next = text.index(after: index)
                if inQuotes, next < text.endIndex, text[next] == "\"" {
                    field.append("\"")
                    index = text.index(after: next)
                    continue
                }
                inQuotes.toggle()
            } else if character == ",", !inQuotes {
                row.append(field)
                field = ""
            } else if (character == "\n" || character == "\r"), !inQuotes {
                if character == "\r" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\n" {
                        index = next
                    }
                }
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(character)
            }
            index = text.index(after: index)
        }

        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}

extension Dictionary where Key == String, Value == String {
    func csvValue(_ possibleHeaders: String...) -> String? {
        for requested in possibleHeaders {
            if let value = self[requested]?.nilIfBlank {
                return value
            }
            let requestedKey = requested.csvHeaderKey
            if let match = first(where: { $0.key.csvHeaderKey == requestedKey })?.value.nilIfBlank {
                return match
            }
        }
        return nil
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    fileprivate var csvHeaderKey: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .filter(\.isLetter)
    }

    mutating func removePrefix(_ prefix: String) {
        guard hasPrefix(prefix) else { return }
        removeFirst(prefix.count)
    }
}

enum ImportedDate {
    private static let formatters: [DateFormatter] = [
        "M/d/yyyy",
        "MM/dd/yyyy",
        "M/d/yy",
        "MM/dd/yy",
        "yyyy-MM-dd"
    ].map { pattern in
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = pattern
        return formatter
    }

    static func storageValue(_ value: String?) -> String? {
        guard let value = value.nilIfBlank else { return nil }
        for formatter in formatters {
            if let date = formatter.date(from: value) {
                return AppDate.storage(date)
            }
        }
        return nil
    }
}
