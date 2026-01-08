#!/bin/bash
set -e

echo "CI post-clone started"

cd "$CI_WORKSPACE"

echo "Installing Flutter deps"
flutter pub get

echo "Precache iOS"
flutter precache --ios

echo "Installing CocoaPods"
cd ios
pod install
cd ..

echo "CI post-clone finished"

