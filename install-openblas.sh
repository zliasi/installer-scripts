#!/usr/bin/env bash
# Install OpenBLAS with version management via symlinks.
#
# Usage: install-openblas.sh [VERSION] [PRECISION]
#
# Arguments:
#   VERSION   - OpenBLAS version (default: 0.3.28)
#   PRECISION - Integer size: lp64 or ilp64 (default: lp64)
#
# Paths:
#   Source: ~/software/src/external
#   Build:  ~/software/build/openblas/VERSION-PRECISION

set -euo pipefail

readonly VERSION="${1:-0.3.28}"
readonly PRECISION="${2:-lp64}"
readonly SRC_DIR="${HOME}/software/src/external"
readonly BUILD_DIR="${HOME}/software/build/openblas/${VERSION}-${PRECISION}"
readonly ARCHIVE="OpenBLAS-${VERSION}.tar.gz"
readonly EXTRACT_DIR="OpenBLAS-${VERSION}"
readonly SOURCE_DIR="${SRC_DIR}/openblas-${VERSION}"

# Validates VERSION and PRECISION parameters.
#
# Exit codes:
#   0 - Parameters valid
#   1 - VERSION empty or PRECISION invalid
validate_parameters() {
  [[ -n "${VERSION}" ]] || {
    echo "Error: VERSION cannot be empty" >&2
    return 1
  }
  [[ "${PRECISION}" =~ ^(lp64|ilp64)$ ]] || {
    echo "Error: PRECISION must be lp64 or ilp64" >&2
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

# Downloads and extracts OpenBLAS source archive.
#
# Exit codes:
#   0 - Download/extraction successful or already extracted
#   1 - Download or extraction failed
download_and_extract() {
  if [[ ! -d "${SOURCE_DIR}" ]]; then
    if [[ -f "${SRC_DIR}/${ARCHIVE}" ]]; then
      echo "Using existing archive: ${ARCHIVE}"
    else
      echo "Downloading OpenBLAS ${VERSION}..."
      wget -P "${SRC_DIR}" "https://github.com/OpenMathLib/OpenBLAS/releases/download/v${VERSION}/${ARCHIVE}" || {
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

# Builds and installs OpenBLAS with specified precision.
#
# Exit codes:
#   0 - Build and installation successful
#   1 - Build or installation failed
build_and_install() {
  cd "${SOURCE_DIR}" || return 1

  make -j "$(nproc)" \
    DYNAMIC_ARCH=1 \
    USE_OPENMP=1 \
    NO_SHARED=0 \
    PREFIX="${BUILD_DIR}" || {
    echo "Error: Build failed" >&2
    return 1
  }

  make \
    DYNAMIC_ARCH=1 \
    USE_OPENMP=1 \
    NO_SHARED=0 \
    PREFIX="${BUILD_DIR}" \
    install || {
    echo "Error: Installation failed" >&2
    return 1
  }
}

# Creates symlink to current OpenBLAS version.
#
# Exit codes:
#   0 - Symlink created successfully
#   1 - Failed to create symlink
setup_symlink() {
  local default_link="${HOME}/software/build/openblas/default"

  rm -f "${default_link}"
  ln -sfn "${VERSION}-${PRECISION}" "${default_link}" || {
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

# Verifies OpenBLAS installation.
#
# Exit codes:
#   0 - Installation verified successfully
#   1 - libopenblas.so not found
verify_installation() {
  [[ -f "${BUILD_DIR}/lib/libopenblas.so" ]] || {
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
