import Presentation
import SwiftUI

/// Library's search, shown when its button is tapped: the field, Cancel, and the model names that start with what was
/// typed.
struct LibrarySearchBar: View {
    @Binding var query: String
    var focused: FocusState<Bool>.Binding
    let rows: [LibraryMediaItem]
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.faint).accessibilityHidden(true)
                    TextField("Prompt words or a model", text: $query)
                        .focused(focused)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                    if !query.isEmpty {
                        Button("Clear", systemImage: "xmark.circle.fill") { query = "" }
                            .labelStyle(.iconOnly)
                            .foregroundStyle(Theme.faint)
                    }
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
                .background(Theme.card, in: .capsule)
                Button("Cancel", action: cancel)
            }
            let models = LibraryBrowse.suggestions(for: query, in: rows, limit: 6)
            if !models.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(models, id: \.self) { name in
                            Button(name) { query = name }
                                .font(.footnote.weight(.semibold))
                                .buttonStyle(.liquidGlass)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
