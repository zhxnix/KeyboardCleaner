#!/bin/bash
# 重新编译并打包 KeyboardCleaner.app（需要 Xcode Command Line Tools）
#
# 签名策略：优先使用本机登录钥匙串中名为 "KeyboardCleaner Dev" 的自签名证书，
# 让代码签名身份在多次重编译之间保持稳定（辅助功能授权不会失效）；
# 没有该证书时退回 ad-hoc 签名。
#
# 首次创建稳定证书（可选，推荐）：
#   1) 用 openssl 生成含 codeSigning 扩展的自签名证书 CN=KeyboardCleaner Dev
#   2) openssl pkcs12 -export -legacy 导出（macOS 只认 legacy 格式）
#   3) security import 导入登录钥匙串
set -euo pipefail
cd "$(dirname "$0")"

APP=KeyboardCleaner.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -o "$APP/Contents/MacOS/KeyboardCleaner" KeyboardCleaner.swift
cp Info.plist "$APP/Contents/Info.plist"

IDENTITY=$(security find-identity 2>/dev/null | grep '"KeyboardCleaner Dev"' | head -1 | sed -n 's/.*"\(.*\)".*/\1/p' || true)
if [ -n "$IDENTITY" ]; then
  echo "使用开发证书签名: ${IDENTITY}（身份稳定，重编译不失效授权）"
  codesign --force --timestamp=none --sign "$IDENTITY" "$APP"
else
  echo "未找到 KeyboardCleaner Dev 证书，使用 ad-hoc 签名（重编译后需重新授予辅助功能权限）"
  codesign --force --sign - "$APP"
fi

echo "✅ 构建完成: $APP"
