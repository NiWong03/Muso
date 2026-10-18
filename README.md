# Muso

Open `MusoStarter.xcodeproj` and run the MusoStarter scheme.

Discovery runs natively through [YouTubeSDK](https://github.com/atpugvaraa/YouTubeSDK), pinned to revision `fa9bd98bafe98cd8d0918d22382001d10cdbe375`. No Python service or YouTube Data API v3 key is required. Google sign-in is optional; see [GOOGLE_SETUP.md](GOOGLE_SETUP.md).

- Search uses YouTubeSDK's broader YouTube Music search and dedicated autocomplete. Search and radio retain unofficial uploads, remixes, and music videos; they are not restricted to official audio tracks. Suggestions wait for a 600 ms typing pause, cancel stale requests, and cache up to 30 queries. Recent searches retain 10 unique entries per account. YouTubeSDK's music search currently returns a single batch without pagination.
- Guest Home uses YouTubeSDK's regional music charts. Signed-in Home requests YouTube Music's Home feed and liked songs, with local Muso listening history shown separately. A library error does not prevent the Home recommendation request.
- Autoplay requests a YouTube Music radio queue based on the current song for guests and signed-in listeners. Already queued tracks and alternate postings with the same normalized artist/title are excluded, preserving upstream order. This is metadata matching, not audio fingerprinting; distinct remixes and live versions remain separate. YouTubeSDK does not yet expose a typed radio endpoint, so `SDKMusicProvider` uses its `NetworkClient` and `MusicResponseParser` adapts the browse/next responses.
- GoogleSignIn refreshes access tokens on the device. The adapter supplies a short-lived bearer token directly to YouTube Music only for account requests (Home and liked songs); public search and song radio never refresh or attach an OAuth token. No cookie login, token files, or backend are used. Live compatibility of the existing OAuth grant with these private endpoints needs a signed-in device check. An error is shown when account access is rejected; guest charts and search remain available.
- YouTubeKit resolves fresh playback streams just before each track plays. The queue stores video metadata rather than expiring stream URLs. Playback, Control Center, background audio, audio interruptions, and route-change handling remain in `AVPlayerService`.
- The mini-player is a native glass tab-bar accessory above Home, Search, and Library. Hold a search result to add it to the end; its three-dot menu offers Play next and Add to end. Tapping a search result starts only that song. In the expanded player, tap Reorder and drag the native list handles, then tap Done, swipe left to remove outside reorder mode, or tap the dots for queue actions. Tap the mini-player title/artwork to expand the player sheet; swipe down or tap the chevron to minimize it. Swipe horizontally across tab content to switch tabs; horizontal shelves and editable text controls retain their gestures. There is no Player tab.

## Verification

Run `sh Tests/run.sh` from this directory. Offline checks cover text entities, search/suggestion separation, direct links, response parsing, queue ordering/exclusions, account-isolated history, persisted queues, and Home behavior. Build with Xcode to validate the third-party SDK and iOS UI integration.

On a device, verify guest charts → search/suggestions → play → expand/minimize → queue completion/autoplay → Control Center → Google sign-in → personalized Home/likes → sign out. Authentication, private API availability, and background playback need live device verification.

Dependencies: YouTubeSDK (above), [Google Sign-In](https://github.com/google/GoogleSignIn-iOS) 9.2.0, and [YouTubeKit](https://github.com/alexeichhorn/YouTubeKit) revision `e5b7d0396ce12bf3444f0d209e8436c83373b7af`.
