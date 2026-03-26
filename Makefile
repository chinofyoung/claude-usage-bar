.PHONY: build run test clean app

APP_NAME = ClaudeUsageBar
APP_BUNDLE = build/$(APP_NAME).app
CONTENTS = $(APP_BUNDLE)/Contents
MACOS = $(CONTENTS)/MacOS
RESOURCES = $(CONTENTS)/Resources

build:
	swift build -c release

test:
	swift test

clean:
	swift package clean
	rm -rf build

# Build a proper .app bundle (required for notifications and LSUIElement)
app: build
	mkdir -p $(MACOS) $(RESOURCES)
	cp .build/release/$(APP_NAME) $(MACOS)/$(APP_NAME)
	cp Resources/Info.plist $(CONTENTS)/Info.plist
	cp Resources/AppIcon.icns $(RESOURCES)/AppIcon.icns
	@echo "Built $(APP_BUNDLE)"

# Run as a proper .app bundle
run: app
	open $(APP_BUNDLE)

# Install to /Applications
install: app
	cp -r $(APP_BUNDLE) /Applications/$(APP_NAME).app
	@echo "Installed to /Applications/$(APP_NAME).app"
