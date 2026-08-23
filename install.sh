#!/usr/bin/env bash
#
# Builds keystone-swift and puts it on your PATH.
#
#   bash install.sh              build and install
#   bash install.sh --uninstall  remove the binary again
#
# Nothing is written outside the build directory and the install directory,
# and --uninstall takes back exactly what was added. A tool that is awkward to
# remove is one people never install in the first place.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
name="keystone-swift"

pick_destination() {
    if [ -n "${KEYSTONE_SWIFT_BIN:-}" ]; then
        echo "$KEYSTONE_SWIFT_BIN"
    elif [ -d "$HOME/.local/bin" ]; then
        echo "$HOME/.local/bin"
    elif [ -w "/usr/local/bin" ]; then
        echo "/usr/local/bin"
    else
        echo "$HOME/.local/bin"
    fi
}

destination="$(pick_destination)"
link="$destination/$name"

if [ "${1:-}" = "--uninstall" ]; then
    if [ -L "$link" ] || [ -f "$link" ]; then
        rm "$link"
        echo "Removed $link"
    else
        echo "Nothing installed at $link"
    fi
    echo
    echo "Hooks in your projects are separate. Remove those with:"
    echo "  keystone-swift uninstall all"
    exit 0
fi

if ! command -v swift >/dev/null 2>&1; then
    echo "Swift is not on your PATH. Install Xcode or a Swift toolchain first." >&2
    exit 1
fi

echo "Building (the first build compiles swift-syntax and takes a minute)..."
swift build -c release --package-path "$here"

binary="$(swift build -c release --package-path "$here" --show-bin-path)/$name"
mkdir -p "$destination"
ln -sf "$binary" "$link"

echo
echo "Linked $link -> $binary"

case ":$PATH:" in
    *":$destination:"*)
        echo
        "$link" version
        echo
        echo "Next, in a project:"
        echo "  keystone-swift init             read the project and write its configuration"
        echo "  keystone-swift check            see where it stands"
        echo "  keystone-swift install claude   refuse violating writes before they land"
        ;;
    *)
        echo
        echo "$destination is not on your PATH. Add this to your shell profile:"
        echo "  export PATH=\"$destination:\$PATH\""
        ;;
esac
