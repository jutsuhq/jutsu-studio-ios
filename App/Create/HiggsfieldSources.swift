import JobEngine
import JutsuCore
import MediaKit
import Presentation
import SwiftUI

/// Higgsfield's Motion Library as a source: pick a clip, it downloads once and becomes Create's source.
struct MotionLibrarySheet: View {
    let library: MotionLibraryModel
    let pick: (MotionPreset) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var loading: String?

    var body: some View {
        @Bindable var library = library
        NavigationStack {
            ScrollView {
                AdaptivePicker(title: "Shelf", selection: $library.shelf) {
                    ForEach(MotionShelf.allCases) { Text($0.title).tag($0) }
                }
                .padding(.horizontal, 16)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                    ForEach(library.current) { preset in
                        Button {
                            loading = preset.id
                            Task {
                                await pick(preset)
                                dismiss()
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                RemoteThumb(url: preset.thumbnailURL)
                                    .frame(height: 190)
                                    .frame(maxWidth: .infinity)
                                    .clipShape(.rect(cornerRadius: 16))
                                    .overlay { if loading == preset.id { ProgressView() } }
                                Text(preset.name)
                                    .font(.caption.weight(.bold))
                                    .textCase(.uppercase)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        .task { if preset.id == library.current.last?.id { await library.loadMore() } }
                    }
                }
                .padding(16)
            }
            .overlay { if library.isLoading && library.current.isEmpty { ProgressView() } }
            .navigationTitle("Motion Library")
            .navigationBarTitleDisplayMode(.inline)
            .closeButton()
            .task(id: library.shelf) { await library.loadIfNeeded() }
        }
    }
}

extension MotionLibraryModel: @retroactive Identifiable {
    nonisolated public var id: ObjectIdentifier { ObjectIdentifier(self) }
}
