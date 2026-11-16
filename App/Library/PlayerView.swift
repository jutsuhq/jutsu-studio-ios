import AVFoundation
import SwiftUI
import UIKit

/// A looping, muted-by-default video filling its frame. `range` plays only that part of the file (a job's source).
struct LoopingPlayer: UIViewRepresentable {
    let url: URL
    var range: ClosedRange<TimeInterval>?
    var isMuted = true
    var gravity: AVLayerVideoGravity = .resizeAspectFill

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.load(url: url, range: range, isMuted: isMuted, gravity: gravity)
        return view
    }

    func updateUIView(_ view: PlayerLayerView, context: Context) {
        view.load(url: url, range: range, isMuted: isMuted, gravity: gravity)
    }

    static func dismantleUIView(_ view: PlayerLayerView, coordinator: ()) {
        view.stop()
    }
}

final class PlayerLayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }  // swiftlint:disable:this force_cast
    private var looper: AVPlayerLooper?
    private var loadedURL: URL?

    func load(url: URL, range: ClosedRange<TimeInterval>?, isMuted: Bool, gravity: AVLayerVideoGravity) {
        playerLayer.videoGravity = gravity
        if let player = playerLayer.player { player.isMuted = isMuted }
        guard loadedURL != url else { return }
        loadedURL = url
        let player = AVQueuePlayer()
        player.isMuted = isMuted
        let item = AVPlayerItem(url: url)
        let timeRange = range.map {
            CMTimeRange(
                start: CMTime(seconds: $0.lowerBound, preferredTimescale: 600),
                end: CMTime(seconds: $0.upperBound, preferredTimescale: 600))
        }
        looper =
            timeRange.map { AVPlayerLooper(player: player, templateItem: item, timeRange: $0) }
            ?? AVPlayerLooper(player: player, templateItem: item)
        playerLayer.player = player
        player.play()
    }

    func stop() {
        playerLayer.player?.pause()
        looper = nil
        playerLayer.player = nil
    }
}
