#!/bin/bash
# tvOS App 自签打包（等 Apple TV 配对后执行）
# 用法：./build-tvos.sh
set -e

TEAM="Y4VQPZFTVA"
BUNDLE="com.yg.qytv"
ARCHIVE="/tmp/QYTV-$(date +%Y%m%d-%H%M).xcarchive"
EXPORT="/tmp/QYTV-export"

echo "▶ 1/3 归档（Release, tvOS）"
xcodebuild -project QYTV.xcodeproj -scheme QYTV \
  -configuration Release -destination 'generic/platform=tvOS' \
  -archivePath "$ARCHIVE" archive \
  DEVELOPMENT_TEAM=$TEAM CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates

echo "▶ 2/3 导出 IPA"
rm -rf "$EXPORT"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT" -exportOptionsPlist ExportOptions.plist \
  -allowProvisioningUpdates

echo "▶ 3/3 结果"
find "$EXPORT" -name "*.ipa" -exec ls -lh {} \;
echo
echo "安装方式（Apple TV 已在同局域网并配对）："
echo "  xcrun devicectl device install app --device <tvOS-UDID> $EXPORT/QYTV.ipa"
echo "或者直接在 Xcode 里 Run 到 Apple TV。"
