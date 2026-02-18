#!/bin/bash

echo "🚀 Restarting PredictBar..."

# 1. Kill the running app if it exists
pkill -x PredictBar
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
rm -rf PredictBar.app
mkdir -p PredictBar.app/Contents/MacOS
mkdir -p PredictBar.app/Contents/Resources

# 4. Copy executable, Info.plist, and resources
cp .build/release/PredictBar PredictBar.app/Contents/MacOS/
cp Info.plist PredictBar.app/Contents/Info.plist
cp Resources/AppIcon.icns PredictBar.app/Contents/Resources/AppIcon.icns

# 5. Update Info.plist placeholders
sed -i '' 's/$(EXECUTABLE_NAME)/PredictBar/g' PredictBar.app/Contents/Info.plist
sed -i '' 's/$(PRODUCT_NAME)/PredictBar/g' PredictBar.app/Contents/Info.plist
sed -i '' 's/$(PRODUCT_BUNDLE_PACKAGE_TYPE)/APPL/g' PredictBar.app/Contents/Info.plist

# 6. Sign app (use ad-hoc by default; set CODESIGN_IDENTITY for your own cert)
#    e.g. CODESIGN_IDENTITY="Apple Development" ./restart.sh
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
echo "✍️  Signing app with identity: $CODESIGN_IDENTITY"
codesign --force --sign "$CODESIGN_IDENTITY" \
    --entitlements PredictBar.entitlements \
    PredictBar.app

# 7. Run the app
echo "🚀 Launching app..."
open PredictBar.app

echo "✨ Done! App restarted."
