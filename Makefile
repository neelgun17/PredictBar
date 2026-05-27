APP_NAME := PredictBar
BUNDLE := $(APP_NAME).app
BUILD_DIR := .build
CODESIGN_IDENTITY ?= -
VERSION ?= $(shell git describe --tags --always 2>/dev/null || echo "dev")
# Strip a leading "v" from tag names like v1.2.3 for CFBundleShortVersionString
SHORT_VERSION := $(patsubst v%,%,$(VERSION))
# Monotonically increasing build number for CFBundleVersion (commit count)
BUILD_NUMBER := $(shell git rev-list --count HEAD 2>/dev/null || echo "1")

# --- Build targets ---

.PHONY: build release run debug clean bundle sign zip dmg help

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

build: ## Build debug binary
	swift build

release: ## Build release binary
	swift build -c release

bundle: release ## Build release + create signed .app bundle
	@echo "📦 Creating $(BUNDLE)..."
	@rm -rf $(BUNDLE)
	@mkdir -p $(BUNDLE)/Contents/MacOS
	@mkdir -p $(BUNDLE)/Contents/Resources
	@cp $(BUILD_DIR)/release/$(APP_NAME) $(BUNDLE)/Contents/MacOS/
	@cp Info.plist $(BUNDLE)/Contents/Info.plist
	@cp Resources/AppIcon.icns $(BUNDLE)/Contents/Resources/AppIcon.icns
	@sed -i '' 's/$$(EXECUTABLE_NAME)/$(APP_NAME)/g' $(BUNDLE)/Contents/Info.plist
	@sed -i '' 's/$$(PRODUCT_NAME)/$(APP_NAME)/g' $(BUNDLE)/Contents/Info.plist
	@sed -i '' 's/$$(PRODUCT_BUNDLE_PACKAGE_TYPE)/APPL/g' $(BUNDLE)/Contents/Info.plist
	@/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(SHORT_VERSION)" $(BUNDLE)/Contents/Info.plist
	@/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(BUILD_NUMBER)" $(BUNDLE)/Contents/Info.plist
	@echo "✍️  Signing with identity: $(CODESIGN_IDENTITY)"
	@codesign --force --sign "$(CODESIGN_IDENTITY)" \
		--options runtime \
		--entitlements $(APP_NAME).entitlements \
		$(BUNDLE)
	@echo "✅ $(BUNDLE) ready"

run: bundle ## Build, bundle, and launch the app
	@pkill -x $(APP_NAME) 2>/dev/null || true
	@open $(BUNDLE)

debug: build ## Build debug and run with console output
	@pkill -x $(APP_NAME) 2>/dev/null || true
	$(BUILD_DIR)/debug/$(APP_NAME)

clean: ## Remove build artifacts and app bundle
	swift package clean
	rm -rf $(BUNDLE)

zip: bundle ## Create a distributable .zip of the .app bundle
	@rm -f $(APP_NAME)-$(VERSION).zip
	ditto -c -k --keepParent $(BUNDLE) $(APP_NAME)-$(VERSION).zip
	@echo "📦 Created $(APP_NAME)-$(VERSION).zip"

dmg: bundle ## Create a distributable .dmg of the .app bundle
	@rm -f $(APP_NAME)-$(VERSION).dmg
	@rm -rf .dmg-staging
	@mkdir -p .dmg-staging
	@cp -R $(BUNDLE) .dmg-staging/
	@ln -s /Applications .dmg-staging/Applications
	hdiutil create -volname "$(APP_NAME)" -srcfolder .dmg-staging -ov -format UDZO $(APP_NAME)-$(VERSION).dmg
	@rm -rf .dmg-staging
	@echo "📦 Created $(APP_NAME)-$(VERSION).dmg"
