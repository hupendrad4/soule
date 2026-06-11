#!/bin/bash
set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 1.0.1"
    exit 1
fi

VERSION=$1

# Validate version format
if ! echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "Error: Version must be in format X.Y.Z"
    exit 1
fi

# Update Info.plist
plutil -replace CFBundleShortVersionString -string "$VERSION" Soulo/Resources/Info.plist

# Update App.xcconfig
sed -i '' "s/MARKETING_VERSION = .*/MARKETING_VERSION = $VERSION/" Soulo/Resources/App.xcconfig

# Commit
git add Soulo/Resources/Info.plist Soulo/Resources/App.xcconfig
git commit -m "chore: bump version to $VERSION"
git tag "v$VERSION"

echo "Version bumped to $VERSION"
echo "Run 'git push --tags' to push the tag."
