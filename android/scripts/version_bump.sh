#!/bin/bash
# Soulo Android Version Bump Script
# Usage: ./scripts/version_bump.sh [major|minor|patch]

set -euo pipefail

GRADLE_PROPERTIES="gradle.properties"

current_major=$(grep "^SOULO_VERSION_MAJOR" "$GRADLE_PROPERTIES" | cut -d= -f2)
current_minor=$(grep "^SOULO_VERSION_MINOR" "$GRADLE_PROPERTIES" | cut -d= -f2)
current_patch=$(grep "^SOULO_VERSION_PATCH" "$GRADLE_PROPERTIES" | cut -d= -f2)
current_code=$(grep "^SOULO_VERSION_CODE" "$GRADLE_PROPERTIES" | cut -d= -f2)

case "${1:-patch}" in
  major)
    new_major=$((current_major + 1))
    new_minor=0
    new_patch=0
    ;;
  minor)
    new_major=$current_major
    new_minor=$((current_minor + 1))
    new_patch=0
    ;;
  patch|*)
    new_major=$current_major
    new_minor=$current_minor
    new_patch=$((current_patch + 1))
    ;;
esac

new_code=$((current_code + 1))

echo "Bumping version: $current_major.$current_minor.$current_patch -> $new_major.$new_minor.$new_patch"
echo "Version code: $current_code -> $new_code"

sed -i '' "s/^SOULO_VERSION_MAJOR=$current_major/SOULO_VERSION_MAJOR=$new_major/" "$GRADLE_PROPERTIES"
sed -i '' "s/^SOULO_VERSION_MINOR=$current_minor/SOULO_VERSION_MINOR=$new_minor/" "$GRADLE_PROPERTIES"
sed -i '' "s/^SOULO_VERSION_PATCH=$current_patch/SOULO_VERSION_PATCH=$new_patch/" "$GRADLE_PROPERTIES"
sed -i '' "s/^SOULO_VERSION_CODE=$current_code/SOULO_VERSION_CODE=$new_code/" "$GRADLE_PROPERTIES"

echo "Done! New version: $new_major.$new_minor.$new_patch (code $new_code)"
