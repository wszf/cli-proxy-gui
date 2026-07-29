#!/bin/bash

set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "${script_directory}/.." && pwd)"
derived_data_path="${repository_root}/.build/DerivedData"

cd "${repository_root}"

xcodebuild \
  -project CLIProxyGUI.xcodeproj \
  -scheme CLIProxyGUI \
  -configuration Debug \
  -destination "platform=macOS" \
  -derivedDataPath "${derived_data_path}" \
  CODE_SIGNING_ALLOWED=NO \
  test
