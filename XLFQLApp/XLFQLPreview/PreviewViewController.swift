import Cocoa
import Quartz

class PreviewViewController: NSViewController, QLPreviewingController {

    private var scrollView: NSScrollView!
    private var tableView: NSTableView!
    private var files: [XLIFFFile] = []

    private enum Row {
        case header(XLIFFFile)
        case unit(TransUnit)
    }
    private var rows: [Row] = []

    // Measurement cell for height calculation
    private lazy var measureField: NSTextField = {
        let tf = NSTextField(wrappingLabelWithString: "")
        tf.maximumNumberOfLines = 0
        tf.lineBreakMode = .byWordWrapping
        return tf
    }()

    override var nibName: NSNib.Name? {
        return NSNib.Name("PreviewViewController")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let parser = XLIFFParser()
        let parsedFiles: [XLIFFFile]

        do {
            parsedFiles = try parser.parse(contentsOf: url)
        } catch {
            await MainActor.run {
                showError("Failed to parse XLIFF: \(error.localizedDescription)")
            }
            return
        }

        await MainActor.run {
            files = parsedFiles
            rows = []
            for file in files {
                rows.append(.header(file))
                for unit in file.transUnits {
                    rows.append(.unit(unit))
                }
            }
            tableView.reloadData()
        }
    }

    private func showError(_ message: String) {
        let label = NSTextField(wrappingLabelWithString: message)
        label.textColor = .systemRed
        label.font = .systemFont(ofSize: 14)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
        ])
    }

    // MARK: - UI Setup

    private func setupUI() {
        scrollView = NSScrollView(frame: view.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false

        tableView = NSTableView()
        tableView.style = .plain
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsColumnResizing = true
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.selectionHighlightStyle = .none

        let idColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("id"))
        idColumn.title = "#"
        idColumn.width = 80
        idColumn.minWidth = 50
        idColumn.maxWidth = 150
        tableView.addTableColumn(idColumn)

        let sourceColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("source"))
        sourceColumn.title = "Source"
        sourceColumn.width = 200
        sourceColumn.minWidth = 100
        tableView.addTableColumn(sourceColumn)

        let targetColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("target"))
        targetColumn.title = "Target"
        targetColumn.width = 200
        targetColumn.minWidth = 100
        tableView.addTableColumn(targetColumn)

        let noteColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("note"))
        noteColumn.title = "Note"
        noteColumn.width = 120
        noteColumn.minWidth = 60
        noteColumn.maxWidth = 300
        tableView.addTableColumn(noteColumn)

        tableView.delegate = self
        tableView.dataSource = self

        scrollView.documentView = tableView
        view.addSubview(scrollView)
    }

    // MARK: - Height Calculation

    private func cellHeight(for string: String, font: NSFont, columnWidth: CGFloat) -> CGFloat {
        guard !string.isEmpty else { return font.pointSize + 6 }
        measureField.stringValue = string
        measureField.font = font
        guard let cell = measureField.cell else { return 20 }
        let bounds = NSRect(x: 0, y: 0, width: columnWidth, height: .greatestFiniteMagnitude)
        return cell.cellSize(forBounds: bounds).height
    }

    private func columnWidth(_ id: String) -> CGFloat {
        for col in tableView.tableColumns where col.identifier.rawValue == id {
            return col.width
        }
        return 200
    }
}

// MARK: - NSTableViewDataSource & Delegate

extension PreviewViewController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        return rows.count
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        if case .header = rows[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        return false
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        switch rows[row] {
        case .header:
            return 24

        case .unit(let unit):
            let sourceH = cellHeight(for: unit.source, font: .systemFont(ofSize: 13), columnWidth: columnWidth("source"))
            let targetH = cellHeight(for: unit.target ?? "—", font: .systemFont(ofSize: 13), columnWidth: columnWidth("target"))
            let noteH = cellHeight(for: unit.note ?? "", font: .systemFont(ofSize: 11), columnWidth: columnWidth("note"))
            return max(max(sourceH, targetH, noteH), 20)
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .header(let file):
            guard tableColumn == nil else { return nil }
            let cellId = NSUserInterfaceItemIdentifier("HeaderCell")
            let cell: NSTextField
            if let existing = tableView.makeView(withIdentifier: cellId, owner: nil) as? NSTextField {
                cell = existing
            } else {
                cell = NSTextField(labelWithString: "")
                cell.identifier = cellId
                cell.font = .systemFont(ofSize: 12, weight: .semibold)
            }

            var label = file.original.isEmpty ? "File" : file.original
            label += "  ·  \(file.sourceLanguage)"
            if let tl = file.targetLanguage {
                label += " → \(tl)"
            }
            cell.stringValue = label
            return cell

        case .unit(let unit):
            guard let columnId = tableColumn?.identifier else { return nil }
            let cellId = NSUserInterfaceItemIdentifier("Cell_\(columnId.rawValue)")
            let cell: NSTextField

            if let existing = tableView.makeView(withIdentifier: cellId, owner: nil) as? NSTextField {
                cell = existing
            } else {
                cell = NSTextField(wrappingLabelWithString: "")
                cell.identifier = cellId
                cell.maximumNumberOfLines = 0
                cell.lineBreakMode = .byWordWrapping
                cell.cell?.wraps = true
                cell.cell?.isScrollable = false
                cell.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            }

            switch columnId.rawValue {
            case "id":
                cell.stringValue = unit.id
                cell.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
                cell.textColor = .secondaryLabelColor
            case "source":
                cell.stringValue = unit.source
                cell.font = .systemFont(ofSize: 13)
                cell.textColor = .labelColor
            case "target":
                if let target = unit.target {
                    cell.stringValue = target
                    cell.font = .systemFont(ofSize: 13)
                    cell.textColor = .labelColor
                } else {
                    cell.stringValue = "—"
                    cell.font = .systemFont(ofSize: 13)
                    cell.textColor = .tertiaryLabelColor
                }
            case "note":
                if let note = unit.note {
                    cell.stringValue = note
                    cell.font = .systemFont(ofSize: 11)
                    cell.textColor = .secondaryLabelColor
                } else {
                    cell.stringValue = ""
                    cell.font = .systemFont(ofSize: 11)
                    cell.textColor = .tertiaryLabelColor
                }
            default:
                break
            }

            return cell
        }
    }
}
