# AK TV for iPhone and iPad

SwiftUI app with the same three tabs as the Android app: Live TV, Movies and Series.

## Build (on a Mac with Xcode 15 or newer)

1. `brew install xcodegen`
2. `cd ios && xcodegen generate`
3. Open `AKTV.xcodeproj`, pick your Team under Signing, and run on an iPhone (iOS 17+).

## How it plays

- **Live TV:** channels come from the TG TV public API. Each channel is played in the native
  iOS player (AVPlayer). The app tries every playable link in turn and skips a link after 15 s.
- **Movies / Series:** catalogue from TMDB, playback from the TGVID player page in a native WebView.

## Known limits (iPhone)

- AVPlayer cannot play MPD / ClearKey (DRM) streams. Channels that only offer those are shown as
  "no stream this iPhone can play right now" until a clear HLS link is available for them.
- The Android app's jjtvxweb and TG page fallbacks are not ported; there is no embedded web player for live channels.
