#!/bin/bash
echo "🚀 Launching KalshiMenuBar in Debug Mode..."
echo "Please click 'Run Backtest' in the app window."
echo "Logs are being captured to debug_output.txt..."

# Kill running instance
pkill KalshiMenuBar || true

# Run executable directly and capture output
./KalshiMenuBar.app/Contents/MacOS/KalshiMenuBar > debug_output.txt 2>&1

echo "App closed."
