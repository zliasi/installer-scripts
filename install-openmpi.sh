#!/usr/bin/env bash
# Install OpenMPI with version management via symlinks.
#
# Usage: install-openmpi.sh [VERSION] [PRECISION]
#
# Arguments:
#   VERSION   - OpenMPI version (default: 5.0.8)
#   PRECISION - Integer size: lp64 or ilp64 (default: lp64)
#
# Paths:
#   Source: ~/software/src/external
#   Build:  ~/software/build/openmpi/VERSION-PRECISION

set -euo pipefail

readonly VERSION="${1:-5.0.8}"
readonly PRECISION="${2:-lp64}"
readonly SRC_DIR="${HOME}/software/src/external"
readonly BUILD_DIR="${HOME}/software/build/openmpi/${VERSION}-${PRECISION}"
readonly ARCHIVE="openmpi-${VERSION}.tar.gz"
readonly SOURCE_DIR="${SRC_DIR}/openmpi-${VERSION}"

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

# Downloads and extracts OpenMPI source archive.
#
# Exit codes:
#   0 - Download/extraction successful or already extracted
#   1 - Download or extraction failed
download_and_extract() {
  if [[ ! -d "${SOURCE_DIR}" ]]; then
    if [[ -f "${SRC_DIR}/${ARCHIVE}" ]]; then
      echo "Using existing archive: ${ARCHIVE}"
    else
      echo "Downloading OpenMPI ${VERSION}..."
      wget -P "${SRC_DIR}" "https://download.open-mpi.org/release/open-mpi/${VERSION}/${ARCHIVE}" || {
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

# Configures, builds, and installs OpenMPI from source.
#
# Exit codes:
#   0 - Build and installation successful
#   1 - Configure, build, or installation failed
build_and_install() {
  cd "${SOURCE_DIR}" || return 1

  ./configure --prefix="${BUILD_DIR}" || {
    echo "Error: Configure failed" >&2
    return 1
  }

  make || {
    echo "Error: Build failed" >&2
    return 1
  }

  make install || {
    echo "Error: Installation failed" >&2
    return 1
  }
}

# Creates symlink to current OpenMPI version.
#
# Exit codes:
#   0 - Symlink created successfully
#   1 - Failed to create symlink
setup_symlink() {
  local default_link="${HOME}/software/build/openmpi/default"

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

# Verifies OpenMPI installation.
#
# Exit codes:
#   0 - Installation verified successfully
#   1 - mpicc executable not found
verify_installation() {
  [[ -x "${BUILD_DIR}/bin/mpicc" ]] || {
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
