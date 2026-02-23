#!/bin/bash
set -euo pipefail
echo "==> Installing firework-agent"

INSTALL_PATH="/usr/bin/firework-agent"
ASSET_NAME="firework-agent-linux-arm64"
TMP_DOWNLOAD_PATH="/tmp/firework-agent.download"
GITHUB_REPO="artemnikitin/firework"
AGENT_GITHUB_TOKEN="${AGENT_GITHUB_TOKEN:-}"

curl_auth_args=()
if [ -n "${AGENT_GITHUB_TOKEN}" ]; then
  # Required for private repositories or when unauthenticated requests are limited.
  curl_auth_args=(-H "Authorization: Bearer ${AGENT_GITHUB_TOKEN}")
fi

download_release_asset() {
  local url="$1"
  if curl -fsSL "${curl_auth_args[@]}" "${url}" -o "${TMP_DOWNLOAD_PATH}"; then
    sudo mv "${TMP_DOWNLOAD_PATH}" "${INSTALL_PATH}"
    sudo chmod +x "${INSTALL_PATH}"
    return 0
  fi
  rm -f "${TMP_DOWNLOAD_PATH}"
  return 1
}

fetch_release_json() {
  local version="$1"
  local api_headers=("${curl_auth_args[@]}" -H "Accept: application/vnd.github+json")

  if [ "${version}" = "latest" ]; then
    if curl -fsSL "${api_headers[@]}" \
      "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" 2>/dev/null; then
      return 0
    fi

    # Fallback when no "latest" release exists (e.g. only prereleases).
    local releases_json
    releases_json="$(curl -fsSL "${api_headers[@]}" \
      "https://api.github.com/repos/${GITHUB_REPO}/releases?per_page=1" 2>/dev/null || true)"
    if [ -z "${releases_json}" ]; then
      return 1
    fi
    printf '%s\n' "${releases_json}" | jq -c '.[0] // empty'
    return 0
  fi

  local version_tag="v${version#v}"
  curl -fsSL "${api_headers[@]}" \
    "https://api.github.com/repos/${GITHUB_REPO}/releases/tags/${version_tag}" 2>/dev/null
}

download_release_asset_via_api() {
  local release_json="$1"
  local asset_id
  asset_id="$(printf '%s\n' "${release_json}" | jq -r --arg name "${ASSET_NAME}" \
    '.assets[]? | select(.name == $name) | .id' | head -n1)"
  if [ -z "${asset_id}" ] || [ "${asset_id}" = "null" ]; then
    return 1
  fi

  local asset_api_url="https://api.github.com/repos/${GITHUB_REPO}/releases/assets/${asset_id}"
  if curl -fsSL "${curl_auth_args[@]}" \
    -H "Accept: application/octet-stream" \
    "${asset_api_url}" -o "${TMP_DOWNLOAD_PATH}"; then
    sudo mv "${TMP_DOWNLOAD_PATH}" "${INSTALL_PATH}"
    sudo chmod +x "${INSTALL_PATH}"
    return 0
  fi

  rm -f "${TMP_DOWNLOAD_PATH}"
  return 1
}

print_private_repo_hint() {
  echo "If the repository is private, provide github_token to Packer."
  echo "Examples:"
  echo "  - packer build -var 'github_token=<token>' ..."
  echo "  - export PKR_VAR_github_token=<token> && packer build ..."
  echo "If using firework-node.auto.pkrvars.hcl, make sure it is loaded by your current packer build command."
}

if [ -n "${AGENT_PATH:-}" ] && [ -f /tmp/firework-agent ] && [ -s /tmp/firework-agent ]; then
  # Use the pre-built binary uploaded by Packer.
  echo "Installing pre-built agent binary"
  sudo mv /tmp/firework-agent "${INSTALL_PATH}"
  sudo chmod +x "${INSTALL_PATH}"
else
  # Download from GitHub releases.
  AGENT_VERSION="${AGENT_VERSION:-latest}"
  VERSION_LABEL="latest"
  if [ "${AGENT_VERSION}" != "latest" ]; then
    VERSION_LABEL="v${AGENT_VERSION#v}"
  fi

  if [ -n "${AGENT_GITHUB_TOKEN}" ]; then
    echo "Downloading firework-agent ${VERSION_LABEL} from GitHub API (token auth)"
    RELEASE_JSON="$(fetch_release_json "${AGENT_VERSION}" || true)"
    if [ -z "${RELEASE_JSON}" ]; then
      echo "ERROR: Could not resolve GitHub release metadata for ${VERSION_LABEL}"
      echo "Make sure github_token has repository contents:read permission"
      exit 1
    fi
    if ! download_release_asset_via_api "${RELEASE_JSON}"; then
      RELEASE_TAG="$(printf '%s\n' "${RELEASE_JSON}" | jq -r '.tag_name // empty')"
      echo "ERROR: Could not download asset ${ASSET_NAME} from release ${RELEASE_TAG:-${VERSION_LABEL}}"
      echo "Make sure the release exists and contains ${ASSET_NAME}"
      exit 1
    fi
  else
    echo "No github_token provided; attempting public release download"
    # Public/no-token mode: use direct release asset URLs.
    if [ "${AGENT_VERSION}" = "latest" ]; then
      echo "Downloading latest firework-agent release from GitHub"
      DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/latest/download/${ASSET_NAME}"
      if ! download_release_asset "${DOWNLOAD_URL}"; then
        RELEASE_JSON="$(fetch_release_json latest || true)"
        RELEASE_TAG="$(printf '%s\n' "${RELEASE_JSON}" | jq -r '.tag_name // empty')"
        if [ -n "${RELEASE_TAG}" ]; then
          FALLBACK_URL="https://github.com/${GITHUB_REPO}/releases/download/${RELEASE_TAG}/${ASSET_NAME}"
          echo "Latest endpoint unavailable, retrying with tag ${RELEASE_TAG}"
          if download_release_asset "${FALLBACK_URL}"; then
            :
          else
            echo "ERROR: Could not download firework-agent from ${FALLBACK_URL}"
            print_private_repo_hint
            exit 1
          fi
        else
          echo "ERROR: Could not resolve latest firework release tag from GitHub"
          print_private_repo_hint
          exit 1
        fi
      fi
    else
      DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/${VERSION_LABEL}/${ASSET_NAME}"
      echo "Downloading firework-agent ${VERSION_LABEL} from GitHub"
      if ! download_release_asset "${DOWNLOAD_URL}"; then
        echo "ERROR: Could not download firework-agent from ${DOWNLOAD_URL}"
        echo "Make sure the requested release exists and includes asset ${ASSET_NAME}"
        print_private_repo_hint
        echo "firework_agent_version accepts: latest, 0.1.0, or v0.1.0"
        echo "Alternatively provide a local binary via firework_agent_path"
        exit 1
      fi
    fi
  fi

  if [ ! -s "${INSTALL_PATH}" ]; then
    echo "ERROR: firework-agent download did not produce a valid binary at ${INSTALL_PATH}"
    echo "Use firework_agent_path to provide a local binary if needed"
    echo "firework_agent_version accepts: latest, 0.1.0, or v0.1.0"
    exit 1
  fi
fi

# Verify.
if [ ! -s "${INSTALL_PATH}" ]; then
  echo "ERROR: firework-agent binary is missing or empty at ${INSTALL_PATH}"
  exit 1
fi

echo "firework-agent installed:"
"${INSTALL_PATH}" --version || true

# Verify the binary is runnable and emits help output.
set +e
HELP_OUTPUT="$("${INSTALL_PATH}" --help 2>&1)"
HELP_STATUS=$?
set -e

if [ -z "${HELP_OUTPUT}" ]; then
  echo "ERROR: firework-agent --help produced no output"
  exit 1
fi

echo "firework-agent --help verification passed (exit code: ${HELP_STATUS})"
printf '%s\n' "${HELP_OUTPUT}"

echo "==> firework-agent installation complete"
