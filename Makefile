DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR

BUILD_DIR := build
APP := $(BUILD_DIR)/Build/Products/Debug/Summon.app

.PHONY: project build run clean

project: Summon.xcodeproj

Summon.xcodeproj: project.yml
	xcodegen generate

build: project
	xcodebuild -project Summon.xcodeproj -scheme Summon -configuration Debug \
		-derivedDataPath $(BUILD_DIR) build

run: build
	@pkill -x Summon || true
	open $(APP)

clean:
	rm -rf $(BUILD_DIR) Summon.xcodeproj
