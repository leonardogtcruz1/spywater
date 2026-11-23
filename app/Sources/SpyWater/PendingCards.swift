import SwiftUI

struct PendingCardView: View {
    let request: PendingRequest
    let isTopmost: Bool
    @EnvironmentObject var store: SessionStore

    var body: some View {
        switch request.kind {
        case .question:
            QuestionCard(request: request)
        case .plan:
            PlanCard(request: request)
        case .permission:
            PermissionCard(request: request, isTopmost: isTopmost)
        }
    }
}

private final class PermissionCardState: ObservableObject {
    @Published var showDenyField = false
    @Published var denyMessage = ""
}

struct PermissionCard: View {
    let request: PendingRequest
    let isTopmost: Bool
    @EnvironmentObject var store: SessionStore
    @StateObject private var ui = PermissionCardState()

    private var elapsed: Int {
        max(0, Int(store.now.timeIntervalSince(request.createdAt)))
    }

    private var remaining: Int? {
        let limit = store.holdSeconds
        guard limit > 0 else { return nil }
        return max(0, limit - elapsed)
    }

    private var firstSuggestionLabel: String? {
        guard let s = request.suggestions.first else { return nil }
        if s.str("type") == "addRules", let rule = s.arr("rules")?.first {
            let tool = rule.str("toolName") ?? request.toolName
            if let content = rule.nonEmptyStr("ruleContent") {
                let short = content.count > 28 ? String(content.prefix(28)) + "…" : content
                return "Sempre permitir \(tool)(\(short))"
            }
            return "Sempre permitir \(tool)"
        }
        if s.str("type") == "setMode", let mode = s.nonEmptyStr("mode") {
            return "Sempre permitir (modo \(mode))"
        }
        return "Permitir sempre"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(request.toolName, systemImage: "hand.raised.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.coral)
                Text(SessionStore.describeTool(request.toolName, input: request.toolInput))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                Spacer()
                Text(timerText)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.60))
            }

            toolDetailView

            if ui.showDenyField {
                HStack(spacing: 8) {
                    TextField("Instrução para o Claude…", text: $ui.denyMessage)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            store.deny(request, message: ui.denyMessage)
                        }
                    Button("Enviar negação") {
                        store.deny(request, message: ui.denyMessage)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.coral)
                    Button("Cancelar") {
                        ui.showDenyField = false
                    }
                    .buttonStyle(.borderless)
                }
            }

            HStack(spacing: 8) {
                if isTopmost {
                    Button("Permitir") {
                        store.allow(request)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.emerald)
                    .keyboardShortcut(.return, modifiers: .command)
                } else {
                    Button("Permitir") {
                        store.allow(request)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.emerald)
                }

                if let suggestion = request.suggestions.first, let label = firstSuggestionLabel {
                    Button(label) {
                        store.allowAlways(request, suggestion: suggestion)
                    }
                    .buttonStyle(.bordered)
                    .lineLimit(1)
                }

                Button("Negar") {
                    store.deny(request)
                }
                .buttonStyle(.bordered)
                .tint(Theme.coral)

                Button("Negar com instrução…") {
                    ui.showDenyField.toggle()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Responder no terminal") {
                    store.release(request)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.white.opacity(0.65))
                .font(.caption)
            }
        }
        .padding(12)
        .background(Theme.coral.opacity(0.11))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.coral.opacity(0.45), lineWidth: 1)
        )
        .cornerRadius(10)
    }

    private var timerText: String {
        if let rem = remaining {
            return "esperando há \(elapsed) s · terminal em \(rem) s"
        }
        return "esperando há \(elapsed) s"
    }

    @ViewBuilder
    private var toolDetailView: some View {
        switch request.toolName {
        case "Bash":
            VStack(alignment: .leading, spacing: 4) {
                if let desc = request.toolInput.nonEmptyStr("description") {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.70))
                }
                let cmd = request.toolInput.str("command") ?? ""
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(cmd)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.95))
                        .textSelection(.enabled)
                        .padding(8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.insetSurface)
                .cornerRadius(6)
            }

        case "Edit", "MultiEdit":
            let path = request.toolInput.str("file_path") ?? ""
            let oldStr: String = {
                if let s = request.toolInput.str("old_string") { return s }
                if let edits = request.toolInput.arr("edits"), let first = edits.first {
                    return first.str("old_string") ?? ""
                }
                return ""
            }()
            let newStr: String = {
                if let s = request.toolInput.str("new_string") { return s }
                if let edits = request.toolInput.arr("edits"), let first = edits.first {
                    return first.str("new_string") ?? ""
                }
                return ""
            }()
            VStack(alignment: .leading, spacing: 6) {
                Text(path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.75))
                HStack(alignment: .top, spacing: 8) {
                    DiffBlock(title: "Remover", text: truncateLines(oldStr, max: 30), tint: Theme.coral)
                    DiffBlock(title: "Adicionar", text: truncateLines(newStr, max: 30), tint: Theme.emerald)
                }
            }

        case "Write":
            let path = request.toolInput.str("file_path") ?? ""
            let content = request.toolInput.str("content") ?? ""
            VStack(alignment: .leading, spacing: 4) {
                Text(path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.75))
                ScrollView {
                    Text(truncateLines(content, max: 30))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.90))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                }
                .frame(maxHeight: 180)
                .background(Theme.insetSurface)
                .cornerRadius(6)
            }

        default:
            let text = truncateLines(prettyJSON(request.toolInput), max: 25)
            ScrollView {
                Text(text)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.90))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
            }
            .frame(maxHeight: 160)
            .background(Theme.insetSurface)
            .cornerRadius(6)
        }
    }

    private func truncateLines(_ s: String, max maxLines: Int) -> String {
        let lines = s.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count <= maxLines { return s }
        return lines.prefix(maxLines).joined(separator: "\n") + "\n… (\(lines.count - maxLines) linhas ocultas)"
    }
}

private struct DiffBlock: View {
    let title: String
    let text: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
            ScrollView {
                Text(text.isEmpty ? "(vazio)" : text)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.90))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(6)
            }
            .frame(maxHeight: 160)
            .background(tint.opacity(0.10))
            .cornerRadius(6)
        }
        .frame(maxWidth: .infinity)
    }
}

private final class QuestionCardState: ObservableObject {
    @Published var singleSelections: [Int: String] = [:]
    @Published var multiSelections: [Int: Set<String>] = [:]
    @Published var otherText: [Int: String] = [:]

    func bindingForOther(index: Int, isMulti: Bool) -> Binding<String> {
        Binding(
            get: { self.otherText[index] ?? "" },
            set: { val in
                self.otherText[index] = val
                if !isMulti && !val.trimmingCharacters(in: .whitespaces).isEmpty {
                    self.singleSelections[index] = nil
                }
            }
        )
    }
}

struct QuestionCard: View {
    let request: PendingRequest
    @EnvironmentObject var store: SessionStore
    @StateObject private var ui = QuestionCardState()

    private var questions: [[String: Any]] {
        request.toolInput.arr("questions") ?? []
    }

    private func answerFor(index: Int, q: [String: Any]) -> String? {
        let isMulti = q.bool("multiSelect") ?? false
        let typed = (ui.otherText[index] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if isMulti {
            var chosen = Array(ui.multiSelections[index] ?? [])
            chosen.sort()
            if !typed.isEmpty {
                chosen.append(typed)
            }
            return chosen.isEmpty ? nil : chosen.joined(separator: ", ")
        } else {
            if !typed.isEmpty {
                return typed
            }
            if let sel = ui.singleSelections[index], !sel.isEmpty {
                return sel
            }
            return nil
        }
    }

    private var allAnswered: Bool {
        guard !questions.isEmpty else { return false }
        for (idx, q) in questions.enumerated() {
            if answerFor(index: idx, q: q) == nil {
                return false
            }
        }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Pergunta do Claude", systemImage: "questionmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.amber)
                Spacer()
                Text("esperando há \(max(0, Int(store.now.timeIntervalSince(request.createdAt)))) s")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.60))
            }

            ForEach(Array(questions.enumerated()), id: \.offset) { idx, q in
                QuestionBlock(index: idx, questionData: q, ui: ui)
            }

            HStack {
                Button("Enviar resposta") {
                    var answers: [String: String] = [:]
                    for (idx, q) in questions.enumerated() {
                        if let qText = q.str("question"), let ans = answerFor(index: idx, q: q) {
                            answers[qText] = ans
                        }
                    }
                    store.answer(request, answers: answers)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.amber)
                .disabled(!allAnswered)

                Spacer()

                Button("Responder no terminal") {
                    store.release(request)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.white.opacity(0.65))
                .font(.caption)
            }
        }
        .padding(12)
        .background(Theme.amber.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.amber.opacity(0.45), lineWidth: 1)
        )
        .cornerRadius(10)
    }
}

private struct QuestionBlock: View {
    let index: Int
    let questionData: [String: Any]
    @ObservedObject var ui: QuestionCardState

    private var header: String? { questionData.nonEmptyStr("header") }
    private var questionText: String { questionData.str("question") ?? "Pergunta \(index + 1)" }
    private var options: [[String: Any]] { questionData.arr("options") ?? [] }
    private var isMulti: Bool { questionData.bool("multiSelect") ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let header {
                    Text(header)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.amber.opacity(0.22))
                        .foregroundStyle(Theme.amber)
                        .cornerRadius(4)
                }
                Text(questionText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
            }

            ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                optionRow(
                    label: opt.str("label") ?? "",
                    description: opt.nonEmptyStr("description")
                )
            }

            HStack(spacing: 6) {
                Text("Outro:")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.70))
                TextField("Digite sua resposta…", text: ui.bindingForOther(index: index, isMulti: isMulti))
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(10)
        .background(Theme.insetSurface)
        .cornerRadius(8)
    }

    @ViewBuilder
    private func optionRow(label: String, description: String?) -> some View {
        let isSelected: Bool = isMulti
            ? (ui.multiSelections[index]?.contains(label) ?? false)
            : (ui.singleSelections[index] == label)

        Button {
            if isMulti {
                var set = ui.multiSelections[index] ?? []
                if set.contains(label) { set.remove(label) } else { set.insert(label) }
                ui.multiSelections[index] = set
            } else {
                ui.singleSelections[index] = label
                ui.otherText[index] = ""
            }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: isMulti
                      ? (isSelected ? "checkmark.square.fill" : "square")
                      : (isSelected ? "largecircle.fill.circle" : "circle"))
                    .foregroundStyle(isSelected ? Theme.aqua : .white.opacity(0.55))
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                    if let description {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                }
                Spacer()
            }
            .padding(6)
            .background(isSelected ? Theme.aqua.opacity(0.16) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

private final class PlanCardState: ObservableObject {
    @Published var showRejectField = false
    @Published var feedback = ""
}

struct PlanCard: View {
    let request: PendingRequest
    @EnvironmentObject var store: SessionStore
    @StateObject private var ui = PlanCardState()

    private var planText: String {
        request.toolInput.nonEmptyStr("plan") ?? "(Plano vazio)"
    }

    private var renderedMarkdown: AttributedString {
        (try? AttributedString(
            markdown: planText,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(planText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Plano pronto para aprovação", systemImage: "doc.text.magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.coral)
                Spacer()
                Text("esperando há \(max(0, Int(store.now.timeIntervalSince(request.createdAt)))) s")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.60))
            }

            ScrollView {
                Text(renderedMarkdown)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .frame(maxHeight: 300)
            .background(Theme.insetSurface)
            .cornerRadius(8)

            if ui.showRejectField {
                HStack(spacing: 8) {
                    TextField("Feedback para ajustar o plano…", text: $ui.feedback)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            store.deny(request, message: ui.feedback)
                        }
                    Button("Enviar feedback") {
                        store.deny(request, message: ui.feedback)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.coral)
                    Button("Cancelar") {
                        ui.showRejectField = false
                    }
                    .buttonStyle(.borderless)
                }
            }

            HStack {
                Button("Aprovar plano") {
                    store.allow(request)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.emerald)

                Button("Rejeitar com feedback…") {
                    ui.showRejectField.toggle()
                }
                .buttonStyle(.bordered)
                .tint(Theme.coral)

                Spacer()

                Button("Responder no terminal") {
                    store.release(request)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.white.opacity(0.65))
                .font(.caption)
            }
        }
        .padding(12)
        .background(Theme.coral.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Theme.coral.opacity(0.45), lineWidth: 1)
        )
        .cornerRadius(10)
    }
}
