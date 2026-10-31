import Cocoa

/// Settings for the matching groups of the Titles list: the ordered list on the left (drag to reorder, which is
/// also the priority), the selected group's editor on the right. Every edit saves immediately.
class MatchingGroupsTab: NSObject {
    private static let sidebarWidth = CGFloat(220)
    private static let minContainerHeight = CGFloat(470)
    private static let predicateEditorHeight = CGFloat(240)
    private static let padding = TableGroupView.padding
    private static var editorWidth: CGFloat { SettingsWindow.contentWidth - sidebarWidth - 1 }
    private static let dragType = NSPasteboard.PasteboardType("com.lwouis.alt-tab-macos.matching-group")
    private static let newGroupFormat = "title CONTAINS[c] \"\""
    private static var shared: MatchingGroupsTab?

    private var items = Preferences.matchingGroups
    private let table = NSTableView()
    private let countButtons = NSSegmentedControl()
    private let pinTopResult = NSButton(checkboxWithTitle: "Pin top result", target: nil, action: nil)
    private let editorStack = NSStackView()
    private let nameField = NSTextField(string: "")
    private let enabledSwitch = NSSwitch()
    private let predicateEditor = NSPredicateEditor()
    private let loadWarning = NSTextField(labelWithString: "This rule couldn't be loaded. Editing it replaces it.")
    private let statusLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(labelWithString: "Add a group with +")

    static func initTab() -> NSView {
        let tab = MatchingGroupsTab()
        shared = tab
        return tab.makeView()
    }

    static func cleanup() {
        shared = nil
    }

    private var selectedIndex: Int? {
        let row = table.selectedRow
        return row >= 0 && row < items.count ? row : nil
    }

    private func makeView() -> NSView {
        let container = makeSidebarEditorContainer(sidebar: makeSidebar(), editor: makeEditorPane(), minHeight: Self.minContainerHeight)
        table.reloadData()
        if !items.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }
        refreshEditor()
        return TableGroupSetView(originalViews: [container], padding: 0, bottomPadding: 0)
    }

    // MARK: - Sidebar

    private func makeSidebar() -> NSView {
        let sidebar = NSView()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.widthAnchor.constraint(equalToConstant: Self.sidebarWidth).isActive = true
        let scrollView = makeTableScrollView()
        configureCountButtons()
        configurePinTopResult()
        sidebar.addSubview(pinTopResult)
        sidebar.addSubview(scrollView)
        sidebar.addSubview(countButtons)
        NSLayoutConstraint.activate([
            pinTopResult.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: Self.padding),
            pinTopResult.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: Self.padding),
            pinTopResult.trailingAnchor.constraint(lessThanOrEqualTo: sidebar.trailingAnchor, constant: -Self.padding),
            scrollView.topAnchor.constraint(equalTo: pinTopResult.bottomAnchor, constant: Self.padding / 2),
            scrollView.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: Self.padding),
            scrollView.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -Self.padding),
            scrollView.bottomAnchor.constraint(equalTo: countButtons.topAnchor, constant: -Self.padding),
            countButtons.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: Self.padding),
            countButtons.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -Self.padding),
        ])
        return sidebar
    }

    private func makeTableScrollView() -> NSScrollView {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 28
        table.style = .inset
        table.allowsEmptySelection = true
        table.dataSource = self
        table.delegate = self
        table.registerForDraggedTypes([Self.dragType])
        table.draggingDestinationFeedbackStyle = .gap
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = table
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        table.backgroundColor = .clear
        return scrollView
    }

    private func configureCountButtons() {
        countButtons.translatesAutoresizingMaskIntoConstraints = false
        countButtons.segmentCount = 2
        countButtons.setImage(NSImage.fromSymbol(.plus, pointSize: 11), forSegment: 0)
        countButtons.setImage(NSImage.fromSymbol(.minus, pointSize: 11), forSegment: 1)
        countButtons.setWidth(28, forSegment: 0)
        countButtons.setWidth(28, forSegment: 1)
        countButtons.trackingMode = .momentary
        countButtons.segmentStyle = .rounded
        countButtons.target = self
        countButtons.action = #selector(countButtonClicked(_:))
    }

    /// Global, like the list of groups: during a search, the best match is drawn first, above the sections.
    private func configurePinTopResult() {
        pinTopResult.translatesAutoresizingMaskIntoConstraints = false
        pinTopResult.toolTip = "While searching, show the best match first, above the groups"
        pinTopResult.state = Preferences.matchingGroupsPinTopResult ? .on : .off
        pinTopResult.target = self
        pinTopResult.action = #selector(pinTopResultChanged)
    }

    @objc private func pinTopResultChanged() {
        Preferences.set("matchingGroupsPinTopResult", String(pinTopResult.state == .on))
    }

    @objc private func countButtonClicked(_ sender: NSSegmentedControl) {
        let segment = sender.selectedSegment
        sender.selectedSegment = -1
        if segment == 0 { addGroup() } else if segment == 1 { removeSelected() }
    }

    /// A new group's rule matches every title, so it would capture everything ranked below it: it starts
    /// disabled, and the user turns it on once the rule says something.
    private func addGroup() {
        items.append(MatchingGroupRule(name: "New group", predicateFormat: Self.newGroupFormat, isEnabled: false))
        save()
        table.reloadData()
        select(items.count - 1)
        nameField.window?.makeFirstResponder(nameField)
    }

    private func removeSelected() {
        guard let index = selectedIndex else { return }
        items.remove(at: index)
        save()
        table.reloadData()
        if !items.isEmpty { select(min(index, items.count - 1)) } else { refreshEditor() }
    }

    private func select(_ index: Int) {
        table.selectRowIndexes([index], byExtendingSelection: false)
        table.scrollRowToVisible(index)
        refreshEditor()
    }

    private func save() {
        Preferences.set("matchingGroups", items)
    }

    // MARK: - Editor

    private func makeEditorPane() -> NSView {
        let pane = NSView()
        pane.translatesAutoresizingMaskIntoConstraints = false
        pane.widthAnchor.constraint(equalToConstant: Self.editorWidth).isActive = true
        configureEditorStack()
        configureEmptyLabel()
        pane.addSubview(editorStack)
        pane.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            editorStack.topAnchor.constraint(equalTo: pane.topAnchor, constant: Self.padding),
            editorStack.leadingAnchor.constraint(equalTo: pane.leadingAnchor, constant: Self.padding),
            editorStack.trailingAnchor.constraint(equalTo: pane.trailingAnchor, constant: -Self.padding),
            editorStack.bottomAnchor.constraint(lessThanOrEqualTo: pane.bottomAnchor, constant: -Self.padding),
            emptyLabel.centerXAnchor.constraint(equalTo: pane.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: pane.centerYAnchor),
        ])
        return pane
    }

    private func configureEditorStack() {
        editorStack.orientation = .vertical
        editorStack.alignment = .leading
        editorStack.spacing = 12
        editorStack.translatesAutoresizingMaskIntoConstraints = false
        let predicateScrollView = makePredicateEditor()
        [makeNameRow(), makeEnabledRow(), makeRuleLabel(), predicateScrollView, loadWarning, statusLabel]
            .forEach { editorStack.addArrangedSubview($0) }
        predicateScrollView.widthAnchor.constraint(equalTo: editorStack.widthAnchor).isActive = true
        loadWarning.textColor = .systemOrange
        statusLabel.textColor = .secondaryLabelColor
    }

    private func configureEmptyLabel() {
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.textColor = .secondaryLabelColor
    }

    private func makeNameRow() -> NSView {
        nameField.placeholderString = "Section name"
        nameField.delegate = self
        nameField.widthAnchor.constraint(equalToConstant: 240).isActive = true
        return row("Name", nameField)
    }

    private func makeEnabledRow() -> NSView {
        enabledSwitch.target = self
        enabledSwitch.action = #selector(enabledChanged)
        return row("Enabled", enabledSwitch)
    }

    private func makeRuleLabel() -> NSView {
        NSTextField(labelWithString: "Windows in this group:")
    }

    private func row(_ title: String, _ control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.widthAnchor.constraint(equalToConstant: 70).isActive = true
        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    /// `NSPredicateEditor` is AppKit's smart-folder rule builder; the predicate it builds is what's stored.
    private func makePredicateEditor() -> NSScrollView {
        predicateEditor.rowTemplates = [makeCompoundTemplate(), makeStringTemplate()]
        predicateEditor.canRemoveAllRows = false
        predicateEditor.target = self
        predicateEditor.action = #selector(predicateChanged)
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(equalToConstant: Self.predicateEditorHeight).isActive = true
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = predicateEditor
        predicateEditor.frame.size.width = Self.editorWidth - Self.padding * 2 - 4
        predicateEditor.autoresizingMask = [.width]
        return scrollView
    }

    private func makeCompoundTemplate() -> NSPredicateEditorRowTemplate {
        NSPredicateEditorRowTemplate(compoundTypes: [NSCompoundPredicate.LogicalType.or, .and, .not].map { NSNumber(value: $0.rawValue) })
    }

    private func makeStringTemplate() -> NSPredicateEditorRowTemplate {
        let operators: [NSComparisonPredicate.Operator] = [.equalTo, .notEqualTo, .contains, .beginsWith, .endsWith, .matches]
        let template = NSPredicateEditorRowTemplate(leftExpressions: MatchingGroupFacts.keys.map { NSExpression(forKeyPath: $0) },
            rightExpressionAttributeType: .stringAttributeType, modifier: .direct,
            operators: operators.map { NSNumber(value: $0.rawValue) },
            options: Int(NSComparisonPredicate.Options.caseInsensitive.rawValue))
        labelFields(template)
        return template
    }

    /// The field popup shows key paths ("bundleId") by default; the items keep their expression, only the title changes.
    private func labelFields(_ template: NSPredicateEditorRowTemplate) {
        let titles = ["title": "Title", "app": "App name", "bundleId": "Bundle ID"]
        if let fields = template.templateViews.first as? NSPopUpButton {
            for item in fields.itemArray {
                guard let keyPath = (item.representedObject as? NSExpression)?.keyPath else { continue }
                item.title = titles[keyPath] ?? keyPath
            }
        }
        if let value = template.templateViews.last as? NSTextField {
            value.placeholderString = "“matches” is a full-string regex, e.g. ^Project.*"
            value.frame.size.width = 260
        }
    }

    private func refreshEditor() {
        guard let index = selectedIndex else {
            editorStack.isHidden = true
            emptyLabel.isHidden = false
            countButtons.setEnabled(false, forSegment: 1)
            return
        }
        let rule = items[index]
        editorStack.isHidden = false
        emptyLabel.isHidden = true
        countButtons.setEnabled(true, forSegment: 1)
        nameField.stringValue = rule.name
        enabledSwitch.state = rule.isEnabled ? .on : .off
        let predicate = MatchingGroups.parse(rule.predicateFormat)
        loadWarning.isHidden = predicate != nil
        loadPredicate(predicate ?? MatchingGroups.parse(Self.newGroupFormat)!)
        refreshStatus(predicate)
    }

    /// The editor only shows a compound row on top when the predicate has one, and without it there is no
    /// Any/All choice to make, so a lone comparison is shown as "Any of" that one comparison.
    private func loadPredicate(_ predicate: NSPredicate) {
        let shown = predicate is NSCompoundPredicate ? predicate : NSCompoundPredicate(orPredicateWithSubpredicates: [predicate])
        ObjCExceptionCatcher.catching { predicateEditor.objectValue = shown }
    }

    private func refreshStatus(_ predicate: NSPredicate?) {
        let count = predicate.map { p in
            Windows.list.filter { $0.shouldShowTheUser && p.evaluate(with: MatchingGroupFacts.of($0.state, $0.application.state)) }.count
        } ?? 0
        statusLabel.stringValue = "Matches \(count) open window\(count == 1 ? "" : "s")"
    }

    private func update(_ change: (inout MatchingGroupRule) -> Void) {
        guard let index = selectedIndex else { return }
        change(&items[index])
        save()
        table.reloadData(forRowIndexes: [index], columnIndexes: [0])
    }

    @objc private func enabledChanged() {
        update { $0.isEnabled = enabledSwitch.state == .on }
    }

    @objc private func predicateChanged() {
        guard let predicate = predicateEditor.predicate else { return }
        update { $0.predicateFormat = predicate.predicateFormat }
        loadWarning.isHidden = true
        refreshStatus(predicate)
    }
}

extension MatchingGroupsTab: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        update { $0.name = nameField.stringValue }
    }
}

extension MatchingGroupsTab: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("cell"), owner: self) as? NSTableCellView ?? makeCell()
        let rule = items[row]
        cell.textField?.stringValue = rule.name.isEmpty ? "Untitled" : rule.name
        cell.textField?.textColor = rule.isEnabled ? .labelColor : .tertiaryLabelColor
        cell.imageView?.isHidden = MatchingGroups.parse(rule.predicateFormat) != nil
        return cell
    }

    private func makeCell() -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = NSUserInterfaceItemIdentifier("cell")
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byTruncatingTail
        let warning = NSImageView(image: NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Rule couldn't be loaded")!)
        warning.contentTintColor = .systemOrange
        warning.setContentCompressionResistancePriority(.required, for: .horizontal)
        let stack = NSStackView(views: [label, warning])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.spacing = 4
        cell.addSubview(stack)
        cell.textField = label
        cell.imageView = warning
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -2),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        refreshEditor()
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString(items[row].id.uuidString, forType: Self.dragType)
        return item
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        dropOperation == .above && draggedIndex(info) != nil ? .move : []
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        guard let from = draggedIndex(info) else { return false }
        let id = items[from].id
        items = items.moved(from: from, to: row)
        save()
        table.reloadData()
        if let index = items.firstIndex(where: { $0.id == id }) { select(index) }
        return true
    }

    private func draggedIndex(_ info: NSDraggingInfo) -> Int? {
        guard let id = info.draggingPasteboard.string(forType: Self.dragType) else { return nil }
        return items.firstIndex { $0.id.uuidString == id }
    }
}
