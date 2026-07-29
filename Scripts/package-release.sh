#!/bin/bash

set -euo pipefail

release_tag="${1:?Usage: ./Scripts/package-release.sh vX.Y.Z}"
if [[ ! "${release_tag}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Release tag must use the vX.Y.Z format." >&2
  exit 1
fi

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "${script_directory}/.." && pwd)"
release_version="${release_tag#v}"
configured_version="$(
  awk -F'"' '/MARKETING_VERSION:/ { print $2; exit }' "${repository_root}/project.yml"
)"

if [[ "${release_version}" != "${configured_version}" ]]; then
  echo "Tag ${release_tag} does not match MARKETING_VERSION ${configured_version}." >&2
  exit 1
fi

release_root="${repository_root}/.build/release"
derived_data_path="${release_root}/DerivedData"
distribution_directory="${release_root}/dist"

rm -rf "${release_root}"
mkdir -p "${distribution_directory}"

cd "${repository_root}"

xcodebuild \
  -project CLIProxyGUI.xcodeproj \
  -scheme CLIProxyGUI \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "${derived_data_path}" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

application_path="${derived_data_path}/Build/Products/Release/CLIProxyGUI.app"
executable_path="${application_path}/Contents/MacOS/CLIProxyGUI"

if [[ ! -d "${application_path}" || ! -f "${executable_path}" ]]; then
  echo "Release application was not produced at ${application_path}." >&2
  exit 1
fi

architectures="$(lipo -archs "${executable_path}")"
if [[ "${architectures}" != *"arm64"* || "${architectures}" != *"x86_64"* ]]; then
  echo "Expected a universal binary, found: ${architectures}" >&2
  exit 1
fi

codesign --force --deep --sign - --timestamp=none "${application_path}"
codesign --verify --deep --strict --verbose=2 "${application_path}"

archive_name="CLIProxy-GUI-${release_tag}-macOS-universal.zip"
archive_path="${distribution_directory}/${archive_name}"
checksum_path="${archive_path}.sha256"

ditto -c -k --norsrc --keepParent "${application_path}" "${archive_path}"

(
  cd "${distribution_directory}"
  shasum -a 256 "${archive_name}" > "$(basename "${checksum_path}")"
)

echo "Created ${archive_path}"
echo "Created ${checksum_path}"
