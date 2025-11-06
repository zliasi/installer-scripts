#!/usr/bin/env bash
# Install Orca from precompiled binaries.
#
# Usage: install-orca.sh [VERSION] [SYMLINK_NAME]
#
# Arguments:
#   VERSION      - Orca version (default: 6.1.0)
#   SYMLINK_NAME - Name for symlink (default: default)
#
# Prerequisites:
#   Source archive must exist at ~/software/src/external/orca-VERSION.tar.xz
#
# Paths:
#   Source: ~/software/src/external
#   Build:  ~/software/build/orca/VERSION

set -euo pipefail

readonly VERSION="${1:-6.1.0}"
readonly SYMLINK_NAME="${2:-default}"
readonly SRC_DIR="${HOME}/software/src/external"
readonly BUILD_DIR="${HOME}/software/build/orca/${VERSION}"
readonly SYMLINK_DIR="$(dirname "${BUILD_DIR}")"
readonly ARCHIVE="orca-${VERSION}.tar.xz"
readonly SOURCE_DIR="${SRC_DIR}/orca-${VERSION}"

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

# Verify source archive exists at expected location
#
# Exit codes:
#   0 - Source archive found
#   1 - Source archive not found
validate_source_exists() {
  [[ -f "${SRC_DIR}/${ARCHIVE}" ]] || {
    echo "Error: Source archive not found at ${SRC_DIR}/${ARCHIVE}" >&2
    echo "Please download Orca ${VERSION} from the forum and place it there" >&2
    return 1
  }
}

# Create build directory
#
# Exit codes:
#   0 - Success
#   1 - Failed to create directory
create_directories() {
  mkdir -p "${BUILD_DIR}" || {
    echo "Error: Failed to create directory" >&2
    return 1
  }
}

# Extract Orca archive if not already extracted
#
# Exit codes:
#   0 - Success or already extracted
#   1 - Extraction failed
extract_archive() {
  if [[ -d "${SOURCE_DIR}" ]]; then
    echo "Source already extracted, skipping"
    return 0
  fi

  echo "Extracting Orca ${VERSION}..."
  tar -xf "${SRC_DIR}/${ARCHIVE}" -C "${SRC_DIR}" || {
    echo "Error: Extraction failed" >&2
    return 1
  }
}

# Copy Orca binaries to build directory
#
# Exit codes:
#   0 - Success
#   1 - Copy failed
copy_binaries() {
  echo "Copying Orca binaries to ${BUILD_DIR}..."
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
  local symlink_path="${SYMLINK_DIR}/${SYMLINK_NAME}"

  rm -f "${symlink_path}"
  ln -sfn "${VERSION}" "${symlink_path}" || {
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

# Verify Orca executable was installed successfully
#
# Exit codes:
#   0 - Success
#   1 - Verification failed
verify_installation() {
  [[ -x "${BUILD_DIR}/orca" ]] || {
    echo "Error: orca executable not found" >&2
    return 1
  }
  echo "Installed to: ${BUILD_DIR}"
}

main() {
  validate_parameters || return 1
  validate_source_exists || return 1
  create_directories || return 1
  extract_archive || return 1
  copy_binaries || return 1
  cleanup_source || return 1
  setup_symlink || return 1
  verify_installation
}

main "$@"
