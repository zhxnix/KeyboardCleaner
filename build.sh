#!/bin/bash
# 重新编译并打包 KeyboardCleaner.app（需要 Xcode Command Line Tools）
set -euo pipefail
cd "$(dirname "$0")"

APP=KeyboardCleaner.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -o "$APP/Contents/MacOS/KeyboardCleaner" KeyboardCleaner.swift
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "✅ 构建完成: $APP"
echo "提示: 重新编译后签名会变化，可能需要在 系统设置 → 隐私与安全性 → 辅助功能 中重新授权"
