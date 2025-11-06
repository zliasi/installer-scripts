#!/usr/bin/env bash
# Install UCX (Unified Communication X) with version management via symlinks.
#
# Usage: install-ucx.sh [VERSION] [SYMLINK_NAME]
#
# Arguments:
#   VERSION      - UCX version (default: 1.15.0)
#   SYMLINK_NAME - Name for symlink (default: default)
#
# Paths:
#   Source: ~/software/src/external
#   Build:  ~/software/build/ucx/VERSION

set -euo pipefail

readonly VERSION="${1:-1.15.0}"
readonly SYMLINK_NAME="${2:-default}"
readonly SRC_DIR="${HOME}/software/src/external"
readonly BUILD_DIR="${HOME}/software/build/ucx/${VERSION}"
readonly SYMLINK_DIR="$(dirname "${BUILD_DIR}")"
readonly ARCHIVE="ucx-${VERSION}.tar.gz"
readonly SOURCE_DIR="${SRC_DIR}/ucx-${VERSION}"

# Validates VERSION parameter is non-empty.
#
# Exit codes:
#   0 - VERSION valid
#   1 - VERSION empty
validate_parameters() {
  [[ -n "${VERSION}" ]] || {
    echo "Error: VERSION cannot be empty" >&2
    return 1
  }
}

# Creates source and build directories.
#
# Exit codes:
#   0 - Directories created successfully
#   1 - Failed to create directories
create_directories() {
  mkdir -p "${SRC_DIR}" "${BUILD_DIR}" || {
    echo "Error: Failed to create directories" >&2
    return 1
  }
}

# Downloads and extracts UCX source archive.
#
# Exit codes:
#   0 - Download/extraction successful or already extracted
#   1 - Download or extraction failed
download_and_extract() {
  if [[ ! -d "${SOURCE_DIR}" ]]; then
    if [[ -f "${SRC_DIR}/${ARCHIVE}" ]]; then
      echo "Using existing archive: ${ARCHIVE}"
    else
      echo "Downloading UCX ${VERSION}..."
      wget -P "${SRC_DIR}" "https://github.com/openucx/ucx/releases/download/v${VERSION}/${ARCHIVE}" || {
        echo "Error: Download failed" >&2
        return 1
      }
    fi
    tar -xf "${SRC_DIR}/${ARCHIVE}" -C "${SRC_DIR}" || {
      echo "Error: Extraction failed" >&2
      return 1
    }
  fi
}

# Configures, builds, and installs UCX from source.
#
# Exit codes:
#   0 - Build and installation successful
#   1 - Configure, build, or installation failed
build_and_install() {
  cd "${SOURCE_DIR}" || return 1

  ./contrib/configure-release --prefix="${BUILD_DIR}" || {
    echo "Error: Configure failed" >&2
    return 1
  }

  make -j "$(nproc)" || {
    echo "Error: Build failed" >&2
    return 1
  }

  make install || {
    echo "Error: Installation failed" >&2
    return 1
  }
}

# Creates symlink to current UCX version.
#
# Exit codes:
#   0 - Symlink created successfully
#   1 - Failed to create symlink
setup_symlink() {
  local symlink_path="${SYMLINK_DIR}/${SYMLINK_NAME}"

  rm -f "${symlink_path}"
  ln -sfn "${VERSION}" "${symlink_path}" || {
    echo "Error: Failed to create symlink" >&2
    return 1
  }
}

# Removes source directory after successful build.
#
# Exit codes:
#   0 - Always succeeds (cleanup warnings are non-fatal)
cleanup_source() {
  if [[ -d "${SOURCE_DIR}" ]]; then
    echo "Removing source directory..."
    rm -rf "${SOURCE_DIR}" || {
      echo "Warning: Failed to remove ${SOURCE_DIR}" >&2
    }
  fi
}

# Verifies UCX installation.
#
# Exit codes:
#   0 - Installation verified successfully
#   1 - ucx library not found
verify_installation() {
  [[ -f "${BUILD_DIR}/lib/libucp.so" ]] || {
    echo "Error: Installation verification failed" >&2
    return 1
  }
  echo "Installed to: ${BUILD_DIR}"
}

main() {
  validate_parameters || return 1
  create_directories || return 1
  download_and_extract || return 1
  build_and_install || return 1
  cleanup_source || return 1
  setup_symlink || return 1
  verify_installation
}

main "$@"
