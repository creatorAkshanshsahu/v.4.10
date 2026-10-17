import SwiftUI
import AVKit
import Combine

/// Native AVPlayer playback for one channel. Tries each playable link in turn; a link that fails or
/// does not start within 15 s is skipped and the next one is tried. No web player, no backup page.
@MainActor
final class PlaybackModel: ObservableObject {
    let player = AVPlayer()
    @Published var loading = true
    @Published var message: String?

    private var candidates: [StreamSource] = []
    private var index = 0
    private var statusSink: AnyCancellable?
    private var timeout: Task<Void, Never>?

    func start(_ channel: Channel) async {
        loading = true; message = nil
        do {
            candidates = try await ChannelAPI.streams(for: channel)
        } catch {
            loading = false; message = "Couldn't reach the channel server. Check your connection."
            return
        }
        guard !candidates.isEmpty else {
            loading = false; message = "This channel has no stream this iPhone can play right now."
            return
        }
        index = 0
        tryCurrent()
    }

    private func tryCurrent() {
        guard index < candidates.count else {
            loading = false; message = "This channel isn't playing right now. Pull down on the list and try again."
            return
        }
        let src = candidates[index]
        let asset = AVURLAsset(url: src.url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": ChannelAPI.userAgent]
        ])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 8
        statusSink = item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                if status == .readyToPlay {
                    self.timeout?.cancel(); self.loading = false; self.message = nil
                } else if status == .failed {
                    self.next()
                }
            }
        player.replaceCurrentItem(with: item)
        player.play()
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if let self, self.loading { self.next() }
            }
        }
    }

    private func next() {
        index += 1
        tryCurrent()
    }

    func stop() {
        timeout?.cancel()
        statusSink = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}

struct PlayerScreen: View {
    let channel: Channel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = PlaybackModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoLayer(player: model.player)
                .ignoresSafeArea()
            if model.loading {
                ProgressView().tint(.white).scaleEffect(1.4)
            }
            if let msg = model.message {
                Text(msg)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding()
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
                    .padding()
            }
        }
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding()
        }
        .overlay(alignment: .top) {
            Text(channel.name)
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.top, 14)
        }
        .task { await model.start(channel) }
        .onDisappear { model.stop() }
    }
}

struct VideoLayer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.allowsPictureInPicturePlayback = true
        vc.showsPlaybackControls = true
        vc.videoGravity = .resizeAspect
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if vc.player !== player { vc.player = player }
    }
}
