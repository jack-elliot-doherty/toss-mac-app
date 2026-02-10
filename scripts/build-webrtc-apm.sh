#!/bin/bash
set -euo pipefail

# Build webrtc-audio-processing as a static XCFramework for macOS (arm64 + x86_64)
# Uses the helloooideeeeea fork: https://github.com/helloooideeeeea/webrtc-audio-processing
# Requires: meson, ninja, pkg-config, abseil (brew install meson ninja pkg-config abseil)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VENDOR_DIR="$PROJECT_DIR/Vendors/webrtc-audio-processing"
BUILD_DIR="$PROJECT_DIR/build-webrtc-apm"
OUTPUT_DIR="$PROJECT_DIR/Frameworks"
WEBRTC_APM_REPO_URL="https://github.com/helloooideeeeea/webrtc-audio-processing.git"
WEBRTC_APM_COMMIT="6a8da66f3a3eafb4ccf0fd3dfbef263e6e60ac17"
MACOS_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET:-13.0}"

echo "=== Building webrtc-audio-processing XCFramework ==="
echo "Project dir: $PROJECT_DIR"
echo "Vendor dir: $VENDOR_DIR"
echo "Pinned commit: $WEBRTC_APM_COMMIT"
echo "Deployment target: macOS $MACOS_DEPLOYMENT_TARGET"

# Bootstrap vendor source if missing.
if [ ! -f "$VENDOR_DIR/meson.build" ]; then
	echo "Vendored source missing. Cloning $WEBRTC_APM_REPO_URL..."
	rm -rf "$VENDOR_DIR"
	git clone "$WEBRTC_APM_REPO_URL" "$VENDOR_DIR"
fi

# Pin vendor source to a deterministic commit when available as a git checkout.
if [ -d "$VENDOR_DIR/.git" ]; then
	current_commit="$(git -C "$VENDOR_DIR" rev-parse HEAD 2>/dev/null || true)"
	if [ "$current_commit" != "$WEBRTC_APM_COMMIT" ]; then
		echo "Checking out pinned commit $WEBRTC_APM_COMMIT (was ${current_commit:-unknown})"
		git -C "$VENDOR_DIR" fetch --depth 1 origin "$WEBRTC_APM_COMMIT"
		git -C "$VENDOR_DIR" checkout --detach "$WEBRTC_APM_COMMIT"
	fi
else
	echo "Warning: $VENDOR_DIR is not a git checkout; commit pin not verified."
fi

if [ ! -f "$VENDOR_DIR/meson.build" ]; then
	echo "Error: webrtc-audio-processing source is incomplete at $VENDOR_DIR"
	exit 1
fi

# Check dependencies
for cmd in meson ninja pkg-config; do
	if ! command -v "$cmd" &>/dev/null; then
		echo "Error: $cmd not found. Install with: brew install $cmd"
		exit 1
	fi
done

# Check abseil
if ! pkg-config --exists absl_base 2>/dev/null; then
	echo "Error: abseil not found. Install with: brew install abseil"
	exit 1
fi

# Clean previous builds
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"/{lib,include}

# Get SDK paths dynamically (don't hardcode Xcode paths)
SDK_PATH=$(xcrun --sdk macosx --show-sdk-path)
CC=$(xcrun -f clang)
CXX=$(xcrun -f clang++)
AR=$(xcrun -f ar)
STRIP=$(xcrun -f strip)

echo "SDK: $SDK_PATH"
echo "CC: $CC"
echo "CXX: $CXX"

# Generate a Meson cross file for a given architecture
generate_cross_file() {
	local arch=$1
	local cross_file="$BUILD_DIR/cross-${arch}.txt"
	local cpu_family
	if [ "$arch" = "arm64" ]; then
		cpu_family="aarch64"
	else
		cpu_family="x86_64"
	fi

	cat > "$cross_file" <<CROSSEOF
[binaries]
c = ['$CC', '-arch', '$arch', '-isysroot', '$SDK_PATH', '-mmacosx-version-min=$MACOS_DEPLOYMENT_TARGET']
cpp = ['$CXX', '-arch', '$arch', '-isysroot', '$SDK_PATH', '-mmacosx-version-min=$MACOS_DEPLOYMENT_TARGET']
ar = '$AR'
strip = '$STRIP'

[built-in options]
c_args = []
cpp_args = []
c_link_args = ['-mmacosx-version-min=$MACOS_DEPLOYMENT_TARGET']
cpp_link_args = ['-mmacosx-version-min=$MACOS_DEPLOYMENT_TARGET']

[properties]
root = '$(dirname "$SDK_PATH")'
has_function_printf = true

[host_machine]
system = 'darwin'
cpu_family = '$cpu_family'
cpu = '$arch'
endian = 'little'
CROSSEOF

	echo "$cross_file"
}

# Build for a single architecture using meson setup + install
build_arch() {
	local arch=$1
	local build_subdir="$BUILD_DIR/build-${arch}"
	local install_subdir="$BUILD_DIR/install-${arch}"
	local cross_file
	cross_file=$(generate_cross_file "$arch")

	echo ""
	echo "=== Building for $arch ==="

	meson setup "$build_subdir" "$VENDOR_DIR" \
		--cross-file "$cross_file" \
		--default-library=static \
		--buildtype=release \
		--prefix="$install_subdir"

	ninja -C "$build_subdir"
	meson install -C "$build_subdir" --no-rebuild

	echo "Installed to: $install_subdir"
	ls -la "$install_subdir/lib/" 2>/dev/null || echo "Warning: no lib dir"
}

# Build both architectures
build_arch arm64
build_arch x86_64

# Merge all static archives for a single architecture deterministically.
merge_archives() {
	local arch=$1
	local lib_dir="$BUILD_DIR/install-${arch}/lib"
	local list_file="$BUILD_DIR/${arch}_libs.txt"
	local merged_out="$BUILD_DIR/lib/libwebrtc-apm-${arch}.a"

	if [ ! -d "$lib_dir" ]; then
		echo "Error: expected lib directory missing: $lib_dir"
		exit 1
	fi

	find "$lib_dir" -type f -name '*.a' | sort > "$list_file"
	local lib_count
	lib_count=$(wc -l < "$list_file" | tr -d ' ')

	if [ "$lib_count" -eq 0 ]; then
		echo "Error: no static archives found under $lib_dir"
		exit 1
	fi

	# macOS ships bash 3.2, so avoid mapfile here.
	# Paths are repo-local with no spaces; sorted list keeps merge deterministic.
	# shellcheck disable=SC2046
	libtool -static -o "$merged_out" $(cat "$list_file")
	echo "Merged $lib_count archives into $merged_out"
}

echo ""
echo "=== Merging static archives per architecture ==="
merge_archives arm64
merge_archives x86_64

echo ""
echo "=== Creating universal binary ==="
lipo -create \
	"$BUILD_DIR/lib/libwebrtc-apm-arm64.a" \
	"$BUILD_DIR/lib/libwebrtc-apm-x86_64.a" \
	-output "$BUILD_DIR/lib/libwebrtc-apm.a"
echo "Universal binary: $BUILD_DIR/lib/libwebrtc-apm.a"
lipo -info "$BUILD_DIR/lib/libwebrtc-apm.a"

# Collect headers from the install tree (arm64 — headers are arch-independent)
echo ""
echo "=== Collecting headers ==="
HEADER_DIR="$BUILD_DIR/include"

INSTALLED_INCLUDE="$BUILD_DIR/install-arm64/include"
if [ -d "$INSTALLED_INCLUDE" ]; then
	cp -R "$INSTALLED_INCLUDE"/* "$HEADER_DIR/" 2>/dev/null || true
	echo "Copied installed headers from meson install"
fi

# The source #include paths are relative to the webrtc/ subdirectory
# (e.g. "modules/audio_processing/include/audio_processing.h", "api/...", "rtc_base/...")
# Copy the full webrtc/ source tree so all transitive includes resolve
if [ -d "$VENDOR_DIR/webrtc" ]; then
	cp -R "$VENDOR_DIR/webrtc"/* "$HEADER_DIR/" 2>/dev/null || true
	echo "Copied webrtc source headers for transitive include resolution"
fi

# Create umbrella header
cat > "$HEADER_DIR/WebRTCAudioProcessing.h" <<'UMBRELLA'
#ifndef WebRTCAudioProcessing_h
#define WebRTCAudioProcessing_h

#include "modules/audio_processing/include/audio_processing.h"

#endif /* WebRTCAudioProcessing_h */
UMBRELLA

echo "Headers collected in: $HEADER_DIR"
echo "Header tree:"
find "$HEADER_DIR" -name "audio_processing.h" 2>/dev/null || echo "Warning: audio_processing.h not found"

# Create XCFramework
echo ""
echo "=== Creating XCFramework ==="
rm -rf "$OUTPUT_DIR/WebRTCAudioProcessing.xcframework"
mkdir -p "$OUTPUT_DIR"

# Build as a library-based xcframework (not framework-based) to avoid module map issues
xcodebuild -create-xcframework \
	-library "$BUILD_DIR/lib/libwebrtc-apm.a" \
	-headers "$HEADER_DIR" \
	-output "$OUTPUT_DIR/WebRTCAudioProcessing.xcframework"

echo "XCFramework created: $OUTPUT_DIR/WebRTCAudioProcessing.xcframework"

# Verify the xcframework structure
echo ""
echo "=== Verification ==="
echo "XCFramework contents:"
ls -la "$OUTPUT_DIR/WebRTCAudioProcessing.xcframework/"
echo ""
echo "Headers check:"
find "$OUTPUT_DIR/WebRTCAudioProcessing.xcframework" -name "audio_processing.h" | head -5

# Link test
echo ""
echo "=== Running link test ==="
LINK_TEST_DIR="$BUILD_DIR/link-test"
mkdir -p "$LINK_TEST_DIR"

# Find the headers inside the xcframework
XCFW_HEADERS=$(find "$OUTPUT_DIR/WebRTCAudioProcessing.xcframework" -type d -name "Headers" | head -1)

cat > "$LINK_TEST_DIR/test.cpp" <<'LINKTEST'
#include "modules/audio_processing/include/audio_processing.h"
int main() {
    auto apm = webrtc::AudioProcessingBuilder().Create();
    return apm ? 0 : 1;
}
LINKTEST

$CXX -std=c++17 \
	-arch arm64 \
	-isysroot "$SDK_PATH" \
	"-mmacosx-version-min=$MACOS_DEPLOYMENT_TARGET" \
	-I"$XCFW_HEADERS" \
	"$LINK_TEST_DIR/test.cpp" \
	"$BUILD_DIR/lib/libwebrtc-apm.a" \
	-lc++ \
	-framework CoreFoundation \
	-o "$LINK_TEST_DIR/test"
echo "Link test PASSED"

# Clean up build artifacts (keep framework)
echo ""
echo "=== Cleanup ==="
rm -rf "$BUILD_DIR"

echo ""
echo "=== Done ==="
echo "Output: $OUTPUT_DIR/WebRTCAudioProcessing.xcframework"
