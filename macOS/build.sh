#!/bin/bash
# Build and sign a universal macOS app using the selected Xcode toolchain.
set -euo pipefail
umask 022

native_dir=$(cd "$(dirname "$0")" && pwd -P)
project_dir=$(cd "$native_dir/.." && pwd -P)
output="$project_dir/dist"
plist="$native_dir/Info.plist"
webpage="$project_dir/web/workspace.html"
for input in "$native_dir/App.swift" "$plist" "$native_dir/AppIcon.icns" "$webpage"; do
    if [[ ! -f "$input" || ! -s "$input" ]]; then
        echo "缺少构建文件：$input" >&2
        exit 1
    fi
done

/usr/bin/plutil -lint "$plist"
name=$(/usr/bin/plutil -extract CFBundleDisplayName raw -o - "$plist")
executable=$(/usr/bin/plutil -extract CFBundleExecutable raw -o - "$plist")
minimum=$(/usr/bin/plutil -extract LSMinimumSystemVersion raw -o - "$plist")
sdk=$(/usr/bin/xcrun --sdk macosx --show-sdk-path)
swiftc=$(/usr/bin/xcrun --sdk macosx --find swiftc)
lipo=$(/usr/bin/xcrun --sdk macosx --find lipo)

mkdir -p "$output"
lock="$output/.build.lock"
if ! /usr/bin/shlock -p "$$" -f "$lock"; then
    echo '另一个构建正在写入 dist。' >&2
    exit 1
fi

stage=''
installing=0
products=("$name.app" "$name.zip")
cleanup() {
    local status=$? keep=0 product
    trap - EXIT INT TERM HUP
    if [[ $installing == 1 ]]; then
        # A failed replacement restores the previous pair from the same volume.
        for product in "${products[@]}"; do
            if [[ ! -e "$stage/new/$product" && -e "$output/$product" ]]; then
                mv "$output/$product" "$stage/new/$product" || keep=1
            fi
            if [[ -e "$stage/previous/$product" ]]; then
                mv "$stage/previous/$product" "$output/$product" || keep=1
            fi
        done
    fi
    if [[ $keep == 1 ]]; then
        echo "已保留恢复所需的文件：$stage" >&2
    elif [[ -n "$stage" ]]; then
        rm -rf "$stage"
    fi
    rm -f "$lock"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

stage=$(/usr/bin/mktemp -d "$output/.assemble.XXXXXXXX")
app="$stage/new/$name.app"
contents="$app/Contents"
binary="$contents/MacOS/$executable"
archive="$stage/new/$name.zip"
mkdir -p "$contents/MacOS" "$contents/Resources" "$stage/previous" "$stage/module-cache"
/usr/bin/install -m 0644 "$plist" "$contents/Info.plist"
/usr/bin/install -m 0644 "$native_dir/AppIcon.icns" "$contents/Resources/AppIcon.icns"
/usr/bin/install -m 0644 "$webpage" "$contents/Resources/workspace.html"

for arch in arm64 x86_64; do
    "$swiftc" -O -parse-as-library -sdk "$sdk" -target "$arch-apple-macos$minimum" \
        -module-cache-path "$stage/module-cache" -framework AppKit -framework WebKit \
        "$native_dir/App.swift" -o "$stage/$arch"
done
"$lipo" -create "$stage/arm64" "$stage/x86_64" -output "$binary"
chmod 0755 "$binary"
/usr/bin/codesign --force --sign - --timestamp=none "$app"
/usr/bin/codesign --verify --all-architectures --deep --strict "$app"

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
/usr/bin/ditto -x -k "$archive" "$stage/check"
extracted="$stage/check/$name.app"
/usr/bin/codesign --verify --all-architectures --deep --strict "$extracted"
"$lipo" "$extracted/Contents/MacOS/$executable" -verify_arch arm64 x86_64
test -x "$extracted/Contents/MacOS/$executable"
cmp "$webpage" "$extracted/Contents/Resources/workspace.html"
cmp "$native_dir/AppIcon.icns" "$extracted/Contents/Resources/AppIcon.icns"

installing=1
for product in "${products[@]}"; do
    if [[ -e "$output/$product" ]]; then mv "$output/$product" "$stage/previous/$product"; fi
    mv "$stage/new/$product" "$output/$product"
done
installing=0
printf '已生成 %s\n' "$output/$name.app" "$output/$name.zip"
