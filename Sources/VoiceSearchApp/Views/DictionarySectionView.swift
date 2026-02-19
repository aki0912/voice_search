import SwiftUI
import VoiceSearchCore

struct DictionarySectionView: View {
    @ObservedObject var viewModel: TranscriptionViewModel
    @State private var isDictionaryExpanded: Bool = false
    @State private var newTermCanonical: String = ""
    @State private var newTermAliases: String = ""
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case canonical, aliases
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isDictionaryExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    TextField("登録語", text: $newTermCanonical)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.regular)
                        .focused($focusedField, equals: .canonical)

                    TextField("同義語（カンマ区切り）", text: $newTermAliases)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.regular)
                        .focused($focusedField, equals: .aliases)

                    Button(action: addEntry) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .disabled(
                        newTermCanonical
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty
                    )
                }

                if !viewModel.dictionaryEntries.isEmpty {
                    List(viewModel.dictionaryEntries, id: \.canonical) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.canonical)
                                    .font(.footnote)
                                    .fontWeight(.medium)
                                if !entry.aliases.isEmpty {
                                    Text(entry.aliases.joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button(action: { viewModel.removeDictionaryEntry(entry) }) {
                                Image(systemName: "trash")
                                    .font(.footnote)
                                    .foregroundStyle(.red.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(minHeight: 80, maxHeight: 160)
                } else {
                    Text("登録された用語はありません")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                }
            }
        } label: {
            HStack {
                Image(systemName: "character.book.closed")
                    .font(.footnote)
                Text("用語辞書")
                    .font(.callout)
                    .fontWeight(.medium)
                if !viewModel.dictionaryEntries.isEmpty {
                    Text("\(viewModel.dictionaryEntries.count)")
                        .font(.caption)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func addEntry() {
        let added = viewModel.addDictionaryEntry(
            canonical: newTermCanonical,
            aliasesText: newTermAliases
        )
        if added {
            newTermCanonical = ""
            newTermAliases = ""
        }
    }
}
