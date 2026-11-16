#if DEBUG
    import Foundation
    import JutsuCore
    import Presentation

    /// A Higgsfield history made of the files in Documents/SampleHistory, for looking at the signed-in Library in the
    /// simulator without an account. Debug builds only, and only with the `-library.sampleHistory YES` launch
    /// argument. A video `name.mp4` uses `name.jpg` as its thumbnail; other pictures are image generations.
    enum SampleHistory {
        static var isOn: Bool { UserDefaults.standard.bool(forKey: "library.sampleHistory") }

        static func page(in documents: URL) -> HistoryPage {
            let folder = documents.appending(path: "SampleHistory", directoryHint: .isDirectory)
            let files =
                ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            let videos = files.filter { $0.pathExtension == "mp4" }
            let posters = Set(videos.map { $0.deletingPathExtension().lastPathComponent })
            let models: [(Mode, VideoModel)] = [
                (.motionTransfer, .seedance25), (.objectSwap, .genjutsu), (.edit, .klingMotionControl),
                (.restyle, .genjutsu),
            ]
            let prompts = [
                "A dancer spins on a neon rooftop at night, rain on the lens, slow push in",
                "Swap the coffee cup for a glowing crystal orb, keep the hands and the light",
                "Turn the street into a snowy evening, warm shop windows, soft falling snow",
                "Claymation style, bright colors, the character waves at the camera",
            ]
            let items = videos.enumerated().map { index, file in
                let (mode, model) = models[index % models.count]
                var item = HistoryItem(
                    id: "sample-video-\(index)", mode: mode, model: model,
                    createdAt: .now.addingTimeInterval(-Double(index) * 5400), isLiked: index == 1, outputURL: file,
                    duration: 5, pixelSize: PixelSize(width: 720, height: 1280), resolution: .p720,
                    prompt: prompts[index % prompts.count], inputs: RemoteInputs(video: nil, images: []))
                item.thumbnailURL = file.deletingPathExtension().appendingPathExtension("jpg")
                return item
            }
            let pictures = files.filter {
                ["png", "jpg"].contains($0.pathExtension)
                    && !posters.contains($0.deletingPathExtension().lastPathComponent)
            }
            let images = pictures.enumerated().map { index, file in
                HistoryImageItem(
                    id: "sample-image-\(index)", prompt: "Portrait of a knight in silver armor, studio light",
                    model: index.isMultiple(of: 2) ? "nano_banana_pro" : "soul_2",
                    createdAt: .now.addingTimeInterval(-Double(index) * 7200 - 1800), outputURL: file,
                    pixelSize: PixelSize(width: 1024, height: 1024))
            }
            return HistoryPage(items: items, images: images, nextCursor: nil)
        }
    }

    /// Launch arguments that open a Library state for a screenshot: `-debug.tab library`, `-debug.source higgsfield`,
    /// `-debug.openFirst YES`, `-debug.showInfo YES`, `-debug.query rooftop`. Debug builds only.
    enum DebugLaunch {
        static var tab: AppTab? { UserDefaults.standard.string(forKey: "debug.tab").flatMap(AppTab.init) }
        static var source: LibrarySource? {
            UserDefaults.standard.string(forKey: "debug.source").flatMap(LibrarySource.init)
        }
        static var opensFirst: Bool { UserDefaults.standard.bool(forKey: "debug.openFirst") }
        static var showsInfo: Bool { UserDefaults.standard.bool(forKey: "debug.showInfo") }
        static var query: String? { UserDefaults.standard.string(forKey: "debug.query") }
    }
#endif
