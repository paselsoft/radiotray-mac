# RadioTray per macOS 10.13 (x86_64). Da eseguire su un Mac con gli strumenti a riga di comando di Xcode.
#   make            compila build/RadioTray
#   make test       test della logica (preferiti, playlist, titoli)
#   make app        crea build/RadioTray.app (firma ad-hoc)
#   make check-mac  verifica architettura, versione minima 10.13, dipendenze e firma
#   make dmg        crea build/RadioTray.dmg
#   make stations   prova a risolvere le stazioni predefinite (richiede Internet)
#   make run        avvia l'app

ARCH       ?= x86_64
MACOS_MIN  ?= 10.13
VERSION    ?= 1.14.0
BUILD      := build
APP        := $(BUILD)/RadioTray.app

CC         := clang
WARN       := -Wall -Wextra -Wno-unused-parameter -Werror=unguarded-availability-new
CFLAGS     := -std=gnu11 -fobjc-arc -fmodules -O2 -g $(WARN) -arch $(ARCH) -mmacosx-version-min=$(MACOS_MIN)
LDFLAGS    := -arch $(ARCH) -mmacosx-version-min=$(MACOS_MIN)
FRAMEWORKS := -framework Cocoa -framework AVFoundation -framework CoreMedia -framework MediaPlayer -framework Carbon -framework CoreAudio -framework SystemConfiguration -framework Security

LOGIC_SRC  := src/RTBookmarks.m src/RTPlaylistParser.m src/RTTrackInfo.m src/RTIcyParser.m src/RTRadioBrowser.m src/RTBookmarksDocument.m src/RTLoginItem.m src/RTFavoriteTracks.m src/RTUpdateChecker.m src/RTArtwork.m src/RTAlarm.m src/RTBackup.m src/RTStationLogo.m
APP_SRC    := $(LOGIC_SRC) src/RTStreamResolver.m src/RTStationChecker.m src/RTHttpsUpgrade.m src/RTScrobbler.m src/RTOnAir.m src/RTLyrics.m src/RTStats.m src/RTIcyMetadataReader.m src/RTArtistWatcher.m src/RTPlayer.m src/RTSettings.m src/RTNotifier.m \
              src/RTStatusIcon.m src/RTSearchWindowController.m src/RTStationEditorController.m src/RTStationCheckWindowController.m src/RTLyricsWindowController.m src/RTProgramsWindowController.m src/RTStatsWindowController.m src/RTFavoritesWindowController.m src/RTTableCell.m src/RTHotKeys.m src/RTAudioWatcher.m src/RTNetworkWatcher.m src/RTAudioOutputs.m src/RTNowPlayingWindowController.m src/RTFileWatcher.m src/RTMediaKeys.m src/RTAppDelegate.m src/main.m
HEADERS    := $(wildcard src/*.h)

# i test girano sull'architettura del runner (Apple Silicon o Intel)
HOST_ARCH  := $(shell uname -m)
TEST_FLAGS := -std=gnu11 -fobjc-arc -fmodules -O0 -g $(WARN) -arch $(HOST_ARCH) -mmacosx-version-min=$(MACOS_MIN)

.PHONY: all test app check-mac dmg stations run clean

all: $(BUILD)/RadioTray

$(BUILD)/RadioTray: $(APP_SRC) $(HEADERS) Makefile
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) $(LDFLAGS) $(APP_SRC) $(FRAMEWORKS) -o $@

$(BUILD)/test_logic: tests/test_logic.m $(LOGIC_SRC) src/RTStreamResolver.m src/RTStationChecker.m src/RTHttpsUpgrade.m src/RTScrobbler.m src/RTOnAir.m src/RTLyrics.m src/RTStats.m src/RTIcyMetadataReader.m src/RTArtistWatcher.m $(HEADERS)
	@mkdir -p $(BUILD)
	$(CC) $(TEST_FLAGS) tests/test_logic.m $(LOGIC_SRC) src/RTStreamResolver.m src/RTStationChecker.m src/RTHttpsUpgrade.m src/RTScrobbler.m src/RTOnAir.m src/RTLyrics.m src/RTStats.m src/RTIcyMetadataReader.m src/RTArtistWatcher.m -framework Foundation -framework Security -o $@

test: $(BUILD)/test_logic
	$(BUILD)/test_logic resources/bookmarks.json resources/stazioni-italiane.json

$(BUILD)/check_stations: tests/check_stations.m $(LOGIC_SRC) src/RTStreamResolver.m src/RTIcyMetadataReader.m $(HEADERS)
	@mkdir -p $(BUILD)
	$(CC) $(TEST_FLAGS) tests/check_stations.m $(LOGIC_SRC) src/RTStreamResolver.m src/RTIcyMetadataReader.m -framework Foundation -o $@

STATIONS   ?= resources/bookmarks.json
stations: $(BUILD)/check_stations
	$(BUILD)/check_stations $(STATIONS)

$(BUILD)/search_stations: tests/search_stations.m $(LOGIC_SRC) $(HEADERS)
	@mkdir -p $(BUILD)
	$(CC) $(TEST_FLAGS) tests/search_stations.m $(LOGIC_SRC) -framework Foundation -o $@

app: $(BUILD)/RadioTray
	VERSION=$(VERSION) sh mac/make_bundle.sh $(APP) $(BUILD)/RadioTray

check-mac: app
	sh mac/check_binaries.sh $(APP) $(ARCH) $(MACOS_MIN)

dmg: app
	sh mac/make_dmg.sh $(APP) $(BUILD)/RadioTray.dmg

run: app
	open $(APP)

clean:
	rm -rf $(BUILD)
