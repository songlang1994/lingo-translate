APP = Lingo Translate
PROJECT = Lingo
SCHEME = Lingo
CONFIG ?= Debug
DERIVED = build
BUNDLE = $(DERIVED)/Build/Products/$(CONFIG)/$(APP).app

.PHONY: build test run stop clean release install

build:
	xcodebuild -project $(PROJECT).xcodeproj -scheme $(SCHEME) -configuration $(CONFIG) -derivedDataPath $(DERIVED) build

test:
	xcodebuild -project $(PROJECT).xcodeproj -scheme $(SCHEME) -configuration Debug -derivedDataPath $(DERIVED) test

run: build
	open "$(BUNDLE)"

stop:
	@osascript -e 'tell application "$(APP)" to quit' 2>/dev/null || true

clean:
	rm -rf $(DERIVED) dist

release:
	xcodebuild -project $(PROJECT).xcodeproj -scheme $(SCHEME) -configuration Release -derivedDataPath $(DERIVED) build
	mkdir -p dist
	ditto -c -k --sequesterRsrc --keepParent "$(DERIVED)/Build/Products/Release/$(APP).app" "dist/$(APP).zip"

install: release
	rm -rf "/Applications/$(APP).app"
	ditto "$(DERIVED)/Build/Products/Release/$(APP).app" "/Applications/$(APP).app"
