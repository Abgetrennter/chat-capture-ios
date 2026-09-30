#!/bin/bash
# Build the iOS app and validate its ordered archive format.
set -euo pipefail
project_root="$(cd "$(dirname "$0")" && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/chat-capture.XXXXXX")"
output_dir="${1:-$project_root/build}"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"

xcrun swiftc "$project_root/ChatCapture/CaptureArchive.swift" "$project_root/tests/main.swift" -o "$build_dir/capture-test"
"$build_dir/capture-test" "$build_dir/fixture.zip"
python3 "$project_root/tests/check_archive.py" "$build_dir/fixture.zip"
xcodebuild -project "$project_root/ChatCapture.xcodeproj" -scheme ChatCapture \
    -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
    -derivedDataPath "$build_dir/DerivedData" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
mkdir "$build_dir/Payload"
ditto "$build_dir/DerivedData/Build/Products/Release-iphoneos/ChatCapture.app" "$build_dir/Payload/ChatCapture.app"
(cd "$build_dir" && /usr/bin/zip -qry ChatCapture-unsigned.ipa Payload)
cp "$build_dir/ChatCapture-unsigned.ipa" "$output_dir/ChatCapture-unsigned.ipa"
printf 'Unsigned IPA: %s\n' "$output_dir/ChatCapture-unsigned.ipa"
