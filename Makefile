DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR

BUILD_DIR := build
INSTALL_DIR := $(HOME)/Applications
# An explicit destination stops xcodebuild warning that "My Mac" matches
# both arm64 and x86_64. Builds are for this Mac's architecture only, which
# is all a local install needs; an App Store archive builds both.
XCODEBUILD := xcodebuild -project Summon.xcodeproj -scheme Summon -derivedDataPath $(BUILD_DIR) \
	-destination 'platform=macOS,arch=$(shell uname -m)'

.DEFAULT_GOAL := build
.PHONY: project build release run install clean

project: Summon.xcodeproj

Summon.xcodeproj: project.yml
	xcodegen generate

# Debug build into build/
build: project
	$(XCODEBUILD) -configuration Debug build

release: project
	$(XCODEBUILD) -configuration Release build

# Debug build, launched from build/
run: build
	@pkill -x Summon || true
	open $(BUILD_DIR)/Build/Products/Debug/Summon.app

# Release build, installed to ~/Applications and relaunched
install: release
	@pkill -x Summon || true
	rm -rf "$(INSTALL_DIR)/Summon.app"
	mkdir -p "$(INSTALL_DIR)"
	ditto $(BUILD_DIR)/Build/Products/Release/Summon.app "$(INSTALL_DIR)/Summon.app"
	open "$(INSTALL_DIR)/Summon.app"

clean:
	rm -rf $(BUILD_DIR) Summon.xcodeproj
