#!/usr/bin/env bash
# Install xtb from precompiled binaries.
#
# Usage: install-xtb.sh [VERSION]
#
# Arguments:
#   VERSION - xtb version (default: 6.7.1)
#
# Paths:
#   Source: ~/software/src/external
#   Build:  ~/software/build/xtb/VERSION

set -euo pipefail

readonly VERSION="${1:-6.7.1}"
readonly SRC_DIR="${HOME}/software/src/external"
readonly BUILD_DIR="${HOME}/software/build/xtb/${VERSION}"
readonly ARCHIVE="xtb-${VERSION}-linux-x86_64.tar.xz"
readonly EXTRACT_DIR="xtb-dist"
readonly SOURCE_DIR="${SRC_DIR}/xtb-${VERSION}"

# Validate required parameters are non-empty
#
# Exit codes:
#   0 - Valid parameters
#   1 - Invalid parameters
validate_parameters() {
  [[ -n "${VERSION}" ]] || {
    echo "Error: VERSION cannot be empty" >&2
    return 1
  }
}

# Create source and build directories
#
# Exit codes:
#   0 - Success
#   1 - Failed to create directories
create_directories() {
  mkdir -p "${SRC_DIR}" "${BUILD_DIR}" || {
    echo "Error: Failed to create directories" >&2
    return 1
  }
}

# Download and extract xtb precompiled binaries
#
# Exit codes:
#   0 - Success or already extracted
#   1 - Download or extraction failed
download_and_extract() {
  if [[ ! -d "${SOURCE_DIR}" ]]; then
    if [[ -f "${SRC_DIR}/${ARCHIVE}" ]]; then
      echo "Using existing archive: ${ARCHIVE}"
    else
      echo "Downloading xtb ${VERSION}..."
      wget -P "${SRC_DIR}" "https://github.com/grimme-lab/xtb/releases/download/v${VERSION}/${ARCHIVE}" || {
        echo "Error: Download failed" >&2
        return 1
      }
    fi
    tar -xf "${SRC_DIR}/${ARCHIVE}" -C "${SRC_DIR}" || {
      echo "Error: Extraction failed" >&2
      return 1
    }
    [[ -d "${SRC_DIR}/${EXTRACT_DIR}" ]] && mv "${SRC_DIR}/${EXTRACT_DIR}" "${SOURCE_DIR}"
  fi
}

# Copy xtb binaries to build directory
#
# Exit codes:
#   0 - Success
#   1 - Copy failed
copy_binaries() {
  echo "Copying xtb binaries to ${BUILD_DIR}..."
  cp -r "${SOURCE_DIR}"/* "${BUILD_DIR}/" || {
    echo "Error: Copy failed" >&2
    return 1
  }
}

# Create default symlink to installed version
#
# Exit codes:
#   0 - Success
#   1 - Failed to create symlink
setup_symlink() {
  local default_link="${HOME}/software/build/xtb/latest"

  rm -f "${default_link}"
  ln -sfn "${VERSION}" "${default_link}" || {
    echo "Error: Failed to create symlink" >&2
    return 1
  }
}

# Remove source directory after installation
#
# Exit codes:
#   0 - Always succeeds (cleanup warnings non-fatal)
cleanup_source() {
  if [[ -d "${SOURCE_DIR}" ]]; then
    echo "Removing source directory..."
    rm -rf "${SOURCE_DIR}" || {
      echo "Warning: Failed to remove ${SOURCE_DIR}" >&2
    }
  fi
}

# Verify xtb executable was installed successfully
#
# Exit codes:
#   0 - Success
#   1 - Verification failed
verify_installation() {
  [[ -x "${BUILD_DIR}/bin/xtb" ]] || {
    echo "Error: xtb executable not found" >&2
    return 1
  }
  echo "Installed to: ${BUILD_DIR}"
}

main() {
  validate_parameters || return 1
  create_directories || return 1
  download_and_extract || return 1
  copy_binaries || return 1
  cleanup_source || return 1
  setup_symlink || return 1
  verify_installation
}

main "$@"
