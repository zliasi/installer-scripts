#!/usr/bin/env bash
# Install GPAW from source with virtual environment.
#
# Usage: install-gpaw.sh [VERSION]
#
# Arguments:
#   VERSION - GPAW version (default: 25.1.0)
#
# Prerequisites:
#   siteconfig.py must exist at ~/software/src/external/gpaw-VERSION/siteconfig.py
#
# Paths:
#   Source: ~/software/src/external
#   Build:  ~/software/build/gpaw/VERSION
#   Venv:   ~/software/build/gpaw/VERSION/venv
#   Data:   ~/software/build/gpaw/VERSION/share

set -euo pipefail

readonly VERSION="${1:-25.1.0}"
readonly SRC_DIR="${HOME}/software/src/external"
readonly BUILD_DIR="${HOME}/software/build/gpaw/${VERSION}"
readonly VENV_DIR="${BUILD_DIR}/venv"
readonly DATA_DIR="${BUILD_DIR}/share"
readonly ARCHIVE="gpaw-${VERSION}.tar.gz"
readonly SOURCE_DIR="${SRC_DIR}/gpaw-${VERSION}"

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

# Verify siteconfig.py exists in source directory
#
# Exit codes:
#   0 - Siteconfig found
#   1 - Siteconfig not found
validate_siteconfig() {
  [[ -f "${SOURCE_DIR}/siteconfig.py" ]] || {
    echo "Error: siteconfig.py not found" >&2
    echo "Required at: ${SOURCE_DIR}/siteconfig.py" >&2
    return 1
  }
}

# Create source, build, and data directories
#
# Exit codes:
#   0 - Success
#   1 - Failed to create directories
create_directories() {
  mkdir -p "${SRC_DIR}" "${BUILD_DIR}" "${DATA_DIR}" || {
    echo "Error: Failed to create directories" >&2
    return 1
  }
}

# Download and extract GPAW source archive
#
# Exit codes:
#   0 - Success or already extracted
#   1 - Download or extraction failed
download_and_extract() {
  if [[ ! -d "${SOURCE_DIR}" ]]; then
    if [[ -f "${SRC_DIR}/${ARCHIVE}" ]]; then
      echo "Using existing archive: ${ARCHIVE}"
    else
      echo "Downloading GPAW ${VERSION}..."
      wget -P "${SRC_DIR}" "https://gitlab.com/gpaw/gpaw/-/archive/${VERSION}/${ARCHIVE}" || {
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

# Create Python virtual environment for GPAW
#
# Exit codes:
#   0 - Success
#   1 - Virtual environment creation failed
create_venv() {
  echo "Creating virtual environment..."
  uv venv "${VENV_DIR}" || {
    echo "Error: Virtual environment creation failed" >&2
    return 1
  }
}

# Install Python dependencies for GPAW
#
# Exit codes:
#   0 - Success
#   1 - Dependency installation failed
install_dependencies() {
  echo "Installing dependencies..."
  uv pip install --upgrade pip wheel setuptools || {
    echo "Error: Failed to upgrade pip" >&2
    return 1
  }
  uv pip install numpy scipy ase mpi4py matplotlib || {
    echo "Error: Failed to install dependencies" >&2
    return 1
  }
}

# Build and install GPAW from source
#
# Exit codes:
#   0 - Success
#   1 - Build or installation failed
build_and_install() {
  cd "${SOURCE_DIR}" || return 1

  echo "Building GPAW from source..."
  uv pip install -vv --no-build-isolation --no-binary=gpaw . || {
    echo "Error: Build failed" >&2
    return 1
  }
}

# Install PAW atomic datasets
#
# Exit codes:
#   0 - Success
#   1 - Dataset installation failed
install_paw_datasets() {
  echo "Installing PAW datasets..."
  gpaw install-data "${DATA_DIR}" || {
    echo "Error: PAW dataset installation failed" >&2
    return 1
  }
}

# Create default symlink to installed version
#
# Exit codes:
#   0 - Success
#   1 - Failed to create symlink
setup_symlink() {
  local default_link="${HOME}/software/build/gpaw/default"

  rm -f "${default_link}"
  ln -sfn "${VERSION}" "${default_link}" || {
    echo "Error: Failed to create symlink" >&2
    return 1
  }
}

# Save installed Python package versions
#
# Exit codes:
#   0 - Success
#   1 - Failed to freeze requirements
freeze_requirements() {
  echo "Freezing requirements..."
  uv pip freeze > "${BUILD_DIR}/requirements.txt" || {
    echo "Error: Failed to freeze requirements" >&2
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

# Verify GPAW was installed successfully
#
# Exit codes:
#   0 - Success
#   1 - Verification failed
verify_installation() {
  gpaw --version || {
    echo "Error: GPAW verification failed" >&2
    return 1
  }
  echo "Installed to: ${BUILD_DIR}"
}

main() {
  validate_parameters || return 1
  validate_siteconfig || return 1
  create_directories || return 1
  download_and_extract || return 1
  create_venv || return 1

  # shellcheck disable=SC1091
  source "${VENV_DIR}/bin/activate" || return 1

  install_dependencies || return 1
  build_and_install || return 1
  install_paw_datasets || return 1
  freeze_requirements || return 1
  cleanup_source || return 1
  setup_symlink || return 1
  verify_installation
}

main "$@"
