#!/usr/bin/env bash
set -euo pipefail

# Support optional version bump type: patch (default), minor, major
BUMP_TYPE=${1:-patch}

# Validate bump type
if [[ ! "$BUMP_TYPE" =~ ^(patch|minor|major)$ ]]; then
  echo "Error: Invalid bump type '$BUMP_TYPE'. Use: patch, minor, or major" >&2
  exit 1
fi

# Test if there are any uncommitted changes
if ! git diff --quiet; then
  echo "Error: Uncommitted changes found in $(pwd)" >&2
  exit 1
fi

echo "Bumping version ($BUMP_TYPE) and build number using fastlane..."

# Use fastlane to increment version number
if [[ "$BUMP_TYPE" == "patch" ]]; then
  VERSION_NUMBER=$(bundle exec fastlane run increment_version_number bump_type:patch xcodeproj:BirdCount.xcodeproj | grep -o "The new version number.*" | sed 's/The new version number is: //')
else
  VERSION_NUMBER=$(bundle exec fastlane run increment_version_number bump_type:"$BUMP_TYPE" xcodeproj:BirdCount.xcodeproj | grep -o "The new version number.*" | sed 's/The new version number is: //')
fi

# Use fastlane to increment build number  
BUILD_NUMBER=$(bundle exec fastlane run increment_build_number xcodeproj:BirdCount.xcodeproj | grep -o "The new build number.*" | sed 's/The new build number is: //')

echo "New version: $VERSION_NUMBER"
echo "New build number: $BUILD_NUMBER"

# Regenerate Xcode project to pick up changes
echo "Regenerating Xcode project..."
bundle exec fastlane generate

# Create git tag v<version>-<build> on current HEAD
TAG="v${VERSION_NUMBER}-${BUILD_NUMBER}"

# Commit current changes
git add project.yml BirdCount.xcodeproj
git commit -m "Bump version to ${VERSION_NUMBER} (${BUILD_NUMBER})"
git tag -a "${TAG}" -m "Release ${VERSION_NUMBER} (${BUILD_NUMBER})"

echo "✅ Version bumped to ${VERSION_NUMBER} (${BUILD_NUMBER})"
echo "✅ Tagged as ${TAG}"