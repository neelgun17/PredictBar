#!/bin/bash

echo "🚀 Restarting KalshiMenuBar..."

# 1. Kill the running app if it exists
pkill -x KalshiMenuBar
echo "✅ Killed existing process"

# 2. Build the release binary
echo "🔨 Building release binary..."
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

# 4. Copy executable and Info.plist
cp .build/release/KalshiMenuBar KalshiMenuBar.app/Contents/MacOS/
cp Info.plist KalshiMenuBar.app/Contents/Info.plist

# 5. Update Info.plist placeholders
sed -i '' 's/$(EXECUTABLE_NAME)/KalshiMenuBar/g' KalshiMenuBar.app/Contents/Info.plist
sed -i '' 's/$(PRODUCT_NAME)/KalshiMenuBar/g' KalshiMenuBar.app/Contents/Info.plist
sed -i '' 's/$(PRODUCT_BUNDLE_PACKAGE_TYPE)/APPL/g' KalshiMenuBar.app/Contents/Info.plist

# 6. Ad-hoc sign the app
echo "✍️  Signing app..."
codesign --force --deep --sign - KalshiMenuBar.app

# 7. Run the app
echo "🚀 Launching app..."
open KalshiMenuBar.app

echo "✨ Done! App restarted."
