APP_NAME = spacemap
BUILD_DIR = .build/release
APP_BUNDLE = $(APP_NAME).app
APP_CONTENTS = $(APP_BUNDLE)/Contents
INSTALL_PATH = /Applications/$(APP_BUNDLE)
VERSION  := $(shell cat VERSION)
ARCHIVE   = spacemap-$(VERSION).zip
STAGE     = spacemap-$(VERSION)

.PHONY: build app install run dev uninstall clean config distconfig permissions archive ls-tool

build:
	swift build -c release

app: build
	mkdir -p $(APP_CONTENTS)/MacOS
	mkdir -p $(APP_CONTENTS)/Resources
	cp $(BUILD_DIR)/$(APP_NAME) $(APP_CONTENTS)/MacOS/
	cp Sources/spacemap/Info.plist $(APP_CONTENTS)/

archive: app
	rm -rf $(STAGE) $(ARCHIVE)
	mkdir -p $(STAGE)
	cp -R $(APP_BUNDLE) $(STAGE)/
	codesign --force --deep --sign - $(STAGE)/$(APP_BUNDLE)
	zip -r --symlinks $(ARCHIVE) $(STAGE)
	rm -rf $(STAGE)
	@echo ""
	@echo "Artifact: $(ARCHIVE)"
	@echo "SHA-256:  $$(shasum -a 256 $(ARCHIVE) | awk '{print $$1}')"
	@echo ""
	@echo "Next: go to https://github.com/jsheffie/spacemap/releases/new"
	@echo "  1. Tag: v$(VERSION)"
	@echo "  2. Click 'Generate release notes'"
	@echo "  3. Attach $(ARCHIVE)"
	@echo "  4. Copy the SHA-256 above into Formula/spacemap.rb in homebrew-tap"

install: app
	mkdir -p $(INSTALL_PATH)/Contents/MacOS
	mkdir -p $(INSTALL_PATH)/Contents/Resources
	cp $(APP_CONTENTS)/MacOS/$(APP_NAME) $(INSTALL_PATH)/Contents/MacOS/
	cp $(APP_CONTENTS)/Info.plist $(INSTALL_PATH)/Contents/
	codesign --force --deep --sign - $(INSTALL_PATH)
	@echo "Installed to $(INSTALL_PATH)"

run: install
	@# Always launch via 'open', never run the binary directly
	open $(INSTALL_PATH)

uninstall:
	-killall $(APP_NAME) 2>/dev/null
	rm -rf $(INSTALL_PATH)
	@echo "Removed $(INSTALL_PATH)"

dev1: uninstall
	@echo ""
	@echo "IMPORTANT: macOS will revok Accessibility permission because the binary will change."
	@echo "Go to System Settings → Privacy & Security → Accessibility"
	@echo "Remove spacemap (− button), you will be prompted to re-add it when we re-install it."

dev2: install
	@# This target kills the app, reinstalls, and relaunches so you just need to re-grant in System Settings.
	-killall $(APP_NAME) 2>/dev/null
	@sleep 0.5
	open $(INSTALL_PATH)
	@echo ""
	@echo "IMPORTANT: you have to give macOS Accessibility permission because the binary changed."
	@echo "Go to System Settings → Privacy & Security → Accessibility"
	@echo "and grant it permissions the prompt that appears."

permissions:
	@echo "If your hotkey stopped working after a reinstall:"
	@echo "  1. killall spacemap"
	@echo "  2. System Settings → Privacy & Security → Accessibility"
	@echo "  3. Click − to remove spacemap"
	@echo "  4. make run   (will prompt for permission again)"
	@echo ""
	@echo "NEVER run the binary directly — always use 'make run' or 'open $(INSTALL_PATH)'"
	@echo "Running the binary directly causes AXIsProcessTrusted() to return false."

ls-tool:
	swift build -c release --product spacemap-ls
	cp $(BUILD_DIR)/spacemap-ls /usr/local/bin/spacemap-ls
	@echo "Installed spacemap-ls to /usr/local/bin/spacemap-ls"

clean:
	rm -rf .build $(APP_BUNDLE)

config:
	mkdir -p ~/.config/spacemap
	@if [ ! -f ~/.config/spacemap/config ]; then \
		echo "GRID_COLS=8" > ~/.config/spacemap/config; \
		echo "GRID_ROWS=2" >> ~/.config/spacemap/config; \
		echo "#CELL_STYLE=rects" >> ~/.config/spacemap/config; \
		echo "CELL_STYLE=icons" >> ~/.config/spacemap/config; \
		echo "#CELL_STYLE=hybrid" >> ~/.config/spacemap/config; \
		echo "#HOTKEY=ctrl+pgdn" >> ~/.config/spacemap/config; \
		echo "#SOCKET_HEALTH_INTERVAL=60" >> ~/.config/spacemap/config; \
		echo "Created ~/.config/spacemap/config with defaults (8x2, icons)"; \
	else \
		echo "Config already exists at ~/.config/spacemap/config"; \
		cat ~/.config/spacemap/config; \
	fi

distconfig:
	mkdir -p ~/.config/spacemap
	@echo "GRID_COLS=8" > ~/.config/spacemap/config
	@echo "GRID_ROWS=2" >> ~/.config/spacemap/config
	@echo "#CELL_STYLE=rects" >> ~/.config/spacemap/config
	@echo "CELL_STYLE=icons" >> ~/.config/spacemap/config
	@echo "#CELL_STYLE=hybrid" >> ~/.config/spacemap/config
	@echo "#HOTKEY=ctrl+pgdn" >> ~/.config/spacemap/config
	@echo "#SOCKET_HEALTH_INTERVAL=60" >> ~/.config/spacemap/config
	@echo "Wrote ~/.config/spacemap/config"
	@cat ~/.config/spacemap/config
