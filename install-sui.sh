#!/usr/bin/env bash

set -Eeuo pipefail

SUI_VERSION="v1.5.4"
SUI_REPO="alireza0/s-ui"
INSTALL_URL="https://raw.githubusercontent.com/${SUI_REPO}/${SUI_VERSION}/install.sh"

echo "======================================"
echo "Grant S-UI Installer"
echo "Version: ${SUI_VERSION}"
echo "======================================"

if [[ "${EUID}" -ne 0 ]]; then
echo "Error: please run as root."
exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
apt-get update
apt-get install -y curl
fi

TEMP_SCRIPT="$(mktemp /tmp/s-ui-install.XXXXXX.sh)"

cleanup() {
rm -f "${TEMP_SCRIPT}"
}

trap cleanup EXIT

echo "Downloading official S-UI installer..."

curl \
--fail \
--location \
--proto '=https' \
--tlsv1.2 \
--retry 3 \
--show-error \
--silent \
"${INSTALL_URL}" \
--output "${TEMP_SCRIPT}"

if [[ ! -s "${TEMP_SCRIPT}" ]]; then
echo "Error: installer is empty."
exit 1
fi

echo "Installer SHA-256:"
sha256sum "${TEMP_SCRIPT}"

echo
echo "Running official installer..."
SUI_LANG=zhcn bash "${TEMP_SCRIPT}" "${SUI_VERSION}"

echo
echo "Installation finished."
echo "Management command: s-ui"
