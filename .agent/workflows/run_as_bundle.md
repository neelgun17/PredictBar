---
description: Build and run the app as a macOS App Bundle to test notifications
---

1. Build the release binary
```bash
swift build -c release
```

2. Create App Bundle structure
```bash
rm -rf KalshiMenuBar.app
mkdir -p KalshiMenuBar.app/Contents/MacOS
mkdir -p KalshiMenuBar.app/Contents/Resources
```

3. Copy executable and Info.plist
```bash
cp .build/release/KalshiMenuBar KalshiMenuBar.app/Contents/MacOS/
cp Info.plist KalshiMenuBar.app/Contents/Info.plist
```

4. Update Info.plist placeholders
```bash
sed -i '' 's/\$(EXECUTABLE_NAME)/KalshiMenuBar/g' KalshiMenuBar.app/Contents/Info.plist
sed -i '' 's/\$(PRODUCT_NAME)/KalshiMenuBar/g' KalshiMenuBar.app/Contents/Info.plist
sed -i '' 's/\$(PRODUCT_BUNDLE_PACKAGE_TYPE)/APPL/g' KalshiMenuBar.app/Contents/Info.plist
```

5. Ad-hoc sign the app (required for notifications and some permissions)
```bash
codesign --force --deep --sign - KalshiMenuBar.app
```

6. Run the app
```bash
open KalshiMenuBar.app
```
