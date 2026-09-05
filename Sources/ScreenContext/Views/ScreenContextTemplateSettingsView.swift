import ScreenContextCore
import SwiftUI

struct ScreenContextTemplateSettingsView: View {
    @Binding var libraryData: Data
    let analytics: TemplateAnalyticsTracker

    @Environment(\.locale) private var locale
    @State private var selectedTemplateID: ScreenContextTemplate.ID?
    @State private var editorSelection: TextSelection?
    @State private var templatePendingDeletion: ScreenContextTemplate?
    @FocusState private var templateNameIsFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            templateList

            Divider()

            templateEditor
        }
        .padding()
        .task {
            repairSelection()
        }
        .onChange(of: libraryData) {
            repairSelection()
        }
        .onChange(of: selectedTemplateID) {
            analytics.flushPendingUpdate()
            editorSelection = nil
            if let selectedTemplate {
                analytics.selected(selectedTemplate)
            }
        }
        .onDisappear {
            analytics.flushPendingUpdate()
        }
        .confirmationDialog(
            "Delete Template?",
            isPresented: deletionIsPresented,
            presenting: templatePendingDeletion
        ) { template in
            Button("Delete template", role: .destructive) {
                delete(template)
            }
        } message: { _ in
            Text("This permanently deletes the template.")
        }
    }

    private var templateList: some View {
        VStack(spacing: 0) {
            List(editableTemplates, selection: $selectedTemplateID) { template in
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    Text( // localization: allow-verbatim user template name
                        verbatim: template.displayName(
                            fallback: String(localized: "New template", locale: locale)
                        )
                    )
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .tag(template.id)
            }
            .listStyle(.bordered)
            .accessibilityLabel("Recording context")

            HStack(spacing: 2) {
                Button(action: addTemplate) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .frame(width: 24, height: 22)
                .accessibilityLabel("Add template")
                .help("Add template")

                Button(action: requestDeleteSelectedTemplate) {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .frame(width: 24, height: 22)
                .accessibilityLabel("Delete template")
                .help("Delete template")
                .disabled(selectedTemplate == nil)

                Button(action: restoreBundledTemplates) {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .frame(width: 24, height: 22)
                .accessibilityLabel("Restore built-in templates")
                .help("Restore built-in templates")
                .disabled(!hasMissingBundledTemplates)

                Spacer()
            }
            .controlSize(.small)
            .padding(.top, 6)
        }
        .frame(
            minWidth: 170,
            idealWidth: 185,
            maxWidth: 210,
            maxHeight: .infinity,
            alignment: .top
        )
    }

    @ViewBuilder
    private var templateEditor: some View {
        if selectedTemplate != nil {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Template name", text: selectedTemplateName)
                    .focused($templateNameIsFocused)

                TextEditor(text: selectedTemplateBody, selection: $editorSelection)
                    .font(.system(.body, design: .monospaced))
                    .padding(6)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.secondary.opacity(0.22))
                    }
                    .accessibilityLabel("Recording context")
                    .id(selectedTemplateID)

                HStack(spacing: 8) {
                    ForEach(ScreenContextTemplateFormatter.placeholders, id: \.self) { placeholder in
                        Button {
                            insert(placeholder)
                        } label: {
                            Text(verbatim: placeholder) // localization: allow-verbatim template syntax
                                .font(.caption.monospaced())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.quaternary, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
            }
        } else {
            Button("Add template", systemImage: "plus", action: addTemplate)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var templates: [ScreenContextTemplate] {
        ScreenContextTemplateLibrary.decode(libraryData)
    }

    private var editableTemplates: [ScreenContextTemplate] {
        templates.filter { $0.id != ScreenContextTemplateLibrary.markdownID }
    }

    private var selectedTemplate: ScreenContextTemplate? {
        editableTemplates.first { $0.id == selectedTemplateID }
    }

    private var hasMissingBundledTemplates: Bool {
        ScreenContextTemplateLibrary.restoringMissingBundledTemplates(
            in: templates
        ) != templates
    }

    private var selectedTemplateName: Binding<String> {
        Binding(
            get: { selectedTemplate?.name ?? "" },
            set: { name in
                updateSelectedTemplate { $0.name = name }
            }
        )
    }

    private var selectedTemplateBody: Binding<String> {
        Binding(
            get: { selectedTemplate?.body ?? "" },
            set: { body in
                updateSelectedTemplate { $0.body = body }
            }
        )
    }

    private var deletionIsPresented: Binding<Bool> {
        Binding(
            get: { templatePendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    templatePendingDeletion = nil
                }
            }
        )
    }

    private func addTemplate() {
        let template = ScreenContextTemplate(
            name: String(localized: "New template", locale: locale),
            body: ScreenContextTemplateFormatter.placeholders.joined(separator: "\n\n")
        )
        var updatedTemplates = templates
        updatedTemplates.append(template)
        persist(updatedTemplates)
        analytics.created(template)
        selectedTemplateID = template.id
        templateNameIsFocused = true
    }

    private func requestDeleteSelectedTemplate() {
        templatePendingDeletion = selectedTemplate
    }

    private func restoreBundledTemplates() {
        let updatedTemplates = ScreenContextTemplateLibrary.restoringMissingBundledTemplates(
            in: templates
        )
        guard updatedTemplates != templates else { return }
        let restoredCount = updatedTemplates.count - templates.count
        persist(updatedTemplates)
        analytics.restoredBundledTemplates(count: restoredCount)
        if selectedTemplateID == nil {
            selectedTemplateID = updatedTemplates.first?.id
        }
    }

    private func delete(_ template: ScreenContextTemplate) {
        let updatedTemplates = templates.filter { $0.id != template.id }
        analytics.deleted(template)
        persist(updatedTemplates)
        templatePendingDeletion = nil
        selectedTemplateID = updatedTemplates.first?.id
    }

    private func updateSelectedTemplate(
        _ update: (inout ScreenContextTemplate) -> Void
    ) {
        guard let selectedTemplateID,
              let index = templates.firstIndex(where: { $0.id == selectedTemplateID }) else {
            return
        }
        var updatedTemplates = templates
        update(&updatedTemplates[index])
        persist(updatedTemplates)
        analytics.scheduleUpdated(updatedTemplates[index])
    }

    private func insert(_ placeholder: String) {
        let body = selectedTemplateBody.wrappedValue
        let replacementRange = selectedRange(in: body)
        let insertion = ScreenContextTemplateEditing.inserting(
            placeholder,
            into: body,
            replacing: replacementRange
        )
        let cursor = insertion.body.index(
            insertion.body.startIndex,
            offsetBy: insertion.cursorOffset
        )
        selectedTemplateBody.wrappedValue = insertion.body
        editorSelection = TextSelection(insertionPoint: cursor)
    }

    private func selectedRange(in body: String) -> Range<String.Index> {
        guard let editorSelection else {
            return body.endIndex..<body.endIndex
        }
        switch editorSelection.indices {
        case let .selection(range):
            return range
        case let .multiSelection(ranges):
            return ranges.ranges.first ?? body.endIndex..<body.endIndex
        @unknown default:
            return body.endIndex..<body.endIndex
        }
    }

    private func persist(_ templates: [ScreenContextTemplate]) {
        guard let data = try? ScreenContextTemplateLibrary.encode(templates) else {
            return
        }
        libraryData = data
    }

    private func repairSelection() {
        guard !editableTemplates.contains(where: { $0.id == selectedTemplateID }) else {
            return
        }
        selectedTemplateID = editableTemplates.first?.id
    }
}
