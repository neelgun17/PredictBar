#!/bin/bash

echo "🚀 Restarting KalshiMenuBar..."

# 1. Kill the running app if it exists
pkill -x KalshiMenuBar
echo "✅ Killed existing process"

# 2. Build the release binary
echo "🔨 Building release binary..."
swift package clean
swift build -c release
if [ $? -ne 0 ]; then
    echo "❌ Build failed"
    exit 1
fi

# 3. Create App Bundle structure
echo "📦 Creating App Bundle..."
rm -rf KalshiMenuBar.app
mkdir -p KalshiMenuBar.app/Contents/MacOS
mkdir -p KalshiMenuBar.app/Contents/Resources

# 4. Copy executable, Info.plist, and resources
cp .build/release/KalshiMenuBar KalshiMenuBar.app/Contents/MacOS/
cp Info.plist KalshiMenuBar.app/Contents/Info.plist
cp Resources/AppIcon.icns KalshiMenuBar.app/Contents/Resources/AppIcon.icns

# 5. Update Info.plist placeholders
sed -i '' 's/$(EXECUTABLE_NAME)/KalshiMenuBar/g' KalshiMenuBar.app/Contents/Info.plist
sed -i '' 's/$(PRODUCT_NAME)/KalshiMenuBar/g' KalshiMenuBar.app/Contents/Info.plist
sed -i '' 's/$(PRODUCT_BUNDLE_PACKAGE_TYPE)/APPL/g' KalshiMenuBar.app/Contents/Info.plist

# 6. Sign app (use ad-hoc by default; set CODESIGN_IDENTITY for your own cert)
#    e.g. CODESIGN_IDENTITY="Apple Development" ./restart.sh
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
echo "✍️  Signing app with identity: $CODESIGN_IDENTITY"
codesign --force --sign "$CODESIGN_IDENTITY" \
    --entitlements KalshiMenuBar.entitlements \
    KalshiMenuBar.app

# 7. Run the app
echo "🚀 Launching app..."
open KalshiMenuBar.app

echo "✨ Done! App restarted."
