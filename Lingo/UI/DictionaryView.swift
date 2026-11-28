import SwiftUI

/// The dictionary card under both columns: pronunciation, part of speech,
/// senses, and examples. The pane fills the height the user chose and scrolls
/// when the entry is taller than that.
struct DictionaryView: View {
    let state: DictionaryState
    /// Source text, used to avoid repeating the headword right under the word.
    let sourceText: String

    private static let topID = "dictionary-top"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                content.id(Self.topID)
            }
            .scrollIndicators(.automatic)
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: state) { _, _ in
                proxy.scrollTo(Self.topID, anchor: .top)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .none:
            EmptyView()
        case let .entry(entry):
            entryContent(entry)
        }
    }

    private func entryContent(_ entry: DictionaryEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let headword = headword(for: entry) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(headword)
                        .font(.system(size: 14, weight: .semibold))
                    if let pronunciation = entry.pronunciation {
                        pronunciationLabel(pronunciation)
                    }
                }
            } else if let pronunciation = entry.pronunciation {
                pronunciationLabel(pronunciation)
            }

            ForEach(Array(entry.senses.enumerated()), id: \.offset) { _, sense in
                senseView(sense)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private func pronunciationLabel(_ pronunciation: String) -> some View {
        Text(pronunciation)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
    }

    /// The headword repeats the source only when it is a different form, such
    /// as the dictionary form of an inflected word.
    private func headword(for entry: DictionaryEntry) -> String? {
        let term = entry.term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return nil }
        let source = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let same = term.compare(source, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        return same ? nil : term
    }

    private func senseView(_ sense: DictionaryEntry.Sense) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if !sense.partOfSpeech.isEmpty {
                    Text(sense.partOfSpeech)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .frame(height: 16)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.primary.opacity(0.07))
                        )
                }
                Text(sense.definition)
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(Array(sense.examples.enumerated()), id: \.offset) { _, example in
                exampleView(example)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func exampleView(_ example: DictionaryEntry.Example) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(example.source)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            if !example.translation.isEmpty {
                Text(example.translation)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 8)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.primary.opacity(0.12))
                .frame(width: 2)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
