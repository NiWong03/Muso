#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d /private/tmp/muso-link-tests.XXXXXX)
swiftc -module-cache-path "$test_dir/cache" -o "$test_dir/tests" \
  MusoStarter/Core/YouTubeVideoInput.swift \
  MusoStarter/Core/MusicCollection.swift \
  MusoStarter/Core/YouTubeModels.swift \
  MusoStarter/Core/YouTubeSearchService.swift \
  MusoStarter/Core/YouTubeMusicProvider.swift \
  MusoStarter/Core/YouTubeDiscoveryService.swift \
  MusoStarter/Core/Catalog/ListeningHistoryStore.swift \
  MusoStarter/Core/Player/PlaybackQueueStore.swift \
  MusoStarter/Features/Home/HomeViewModel.swift \
  MusoStarter/Core/Player/PlayerModels.swift \
  MusoStarter/Features/Search/SearchViewModel.swift Tests/YouTubeLinkTests.swift Tests/YouTubeSearchTests.swift Tests/PersonalizationTests.swift
"$test_dir/tests"
swiftc -module-cache-path "$test_dir/cache" -o "$test_dir/lyrics-tests" \
  MusoStarter/Core/YouTubeModels.swift MusoStarter/Core/Player/PlayerModels.swift \
  MusoStarter/Core/LyricaService.swift MusoStarter/Core/VideoArtistResolver.swift Tests/LyricaTests.swift
"$test_dir/lyrics-tests"
