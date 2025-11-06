#!/usr/bin/env bash
# Install libxc with version management via symlinks.
#
# Usage: install-libxc.sh [VERSION]
#
# Arguments:
#   VERSION - libxc version (default: 7.0.0)
#
# Paths:
#   Source: ~/software/src/external
#   Build:  ~/software/build/libxc/VERSION

set -euo pipefail

readonly VERSION="${1:-7.0.0}"
readonly SRC_DIR="${HOME}/software/src/external"
readonly BUILD_DIR="${HOME}/software/build/libxc/${VERSION}"
readonly ARCHIVE="libxc-${VERSION}.tar.bz2"
readonly SOURCE_DIR="${SRC_DIR}/libxc-${VERSION}"

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

# Download and extract libxc source archive
#
# Exit codes:
#   0 - Success or already extracted
#   1 - Download or extraction failed
download_and_extract() {
  if [[ ! -d "${SOURCE_DIR}" ]]; then
    if [[ -f "${SRC_DIR}/${ARCHIVE}" ]]; then
      echo "Using existing archive: ${ARCHIVE}"
    else
      echo "Downloading libxc ${VERSION}..."
      wget -P "${SRC_DIR}" "https://gitlab.com/libxc/libxc/-/archive/${VERSION}/${ARCHIVE}" || {
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

# Configure, build, and install libxc
#
# Exit codes:
#   0 - Success
#   1 - Configuration, build, or installation failed
build_and_install() {
  local build_subdir="${BUILD_DIR}/build"
  mkdir -p "${build_subdir}" || return 1

  cd "${build_subdir}" || return 1

  echo "Configuring libxc ${VERSION}..."
  cmake "${SOURCE_DIR}" \
    -DCMAKE_INSTALL_PREFIX="${BUILD_DIR}" \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DBUILD_SHARED_LIBS=ON \
    -DBUILD_TESTING=OFF || {
    echo "Error: Configuration failed" >&2
    return 1
  }

  echo "Building libxc..."
  cmake --build . || {
    echo "Error: Build failed" >&2
    return 1
  }

  echo "Installing libxc..."
  cmake --install . || {
    echo "Error: Installation failed" >&2
    return 1
  }
}

# Create default symlink to installed version
#
# Exit codes:
#   0 - Success
#   1 - Failed to create symlink
setup_symlink() {
  local default_link="${HOME}/software/build/libxc/latest"

  rm -f "${default_link}"
  ln -sfn "${VERSION}" "${default_link}" || {
    echo "Error: Failed to create symlink" >&2
    return 1
  }
}

# Remove source directory after build
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

# Verify libxc library was installed successfully
#
# Exit codes:
#   0 - Success
#   1 - Verification failed
verify_installation() {
  [[ -f "${BUILD_DIR}/lib/libxc.so" ]] || {
    echo "Error: libxc.so not found" >&2
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
