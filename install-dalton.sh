#!/usr/bin/env bash
# Install Dalton with version management via symlinks.
#
# Usage: install-dalton.sh [VERSION] [PRECISION]
#
# Arguments:
#   VERSION   - Release version (e.g., 2025.0) (default: 2025.0)
#   PRECISION - Integer size: lp64 or ilp64 (default: lp64)
#
# Paths:
#   Source: ~/software/src/external
#   Build:  ~/software/build/dalton/VERSION-PRECISION

set -euo pipefail

readonly VERSION="${1:-2025.0}"
readonly GIT_REF="v${VERSION#v}"
readonly PRECISION="${2:-lp64}"
readonly SRC_DIR="${HOME}/software/src/external"
readonly TEMP_SOURCE_DIR="${SRC_DIR}/dalton-${VERSION}"

if [[ "${VERSION}" =~ ^[0-9] ]]; then
  readonly IS_DEV=false
  PATH_VERSION="${VERSION}"
else
  readonly IS_DEV=true
  PATH_VERSION=""
fi

SOURCE_DIR="${TEMP_SOURCE_DIR}"
BUILD_DIR=""

readonly OPENMPI_DIR="${HOME}/software/build/openmpi/default"
readonly OPENBLAS_DIR="${HOME}/software/build/openblas/default"

# Extract version string from repository files
#
# Exit codes:
#   0 - Version extracted successfully
#   1 - Version not found
extract_version_from_repo() {
  local repo_dir="$1"

  if [[ -f "${repo_dir}/VERSION" ]]; then
    tr -d ' \n' < "${repo_dir}/VERSION"
    return 0
  fi

  if [[ -f "${repo_dir}/setup.py" ]]; then
    grep -oP "version\s*=\s*['\"]?\K[^'\"]*" "${repo_dir}/setup.py" | head -1 | tr -d ' \n'
    return 0
  fi

  return 1
}

# Generate development version string from repository
#
# Exit codes:
#   0 - Always succeeds
determine_dev_version() {
  local repo_dir="$1"
  local extracted

  extracted=$(extract_version_from_repo "${repo_dir}" 2>/dev/null || true)

  if [[ -n "${extracted}" ]]; then
    echo "${extracted}-dev"
  else
    date +%Y.%m-dev
  fi
}

# Validate required parameters
#
# Exit codes:
#   0 - Valid parameters
#   1 - Invalid parameters
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

# Check required dependencies are installed
#
# Exit codes:
#   0 - All dependencies found
#   1 - Missing dependencies
validate_dependencies() {
  [[ -d "${OPENMPI_DIR}" ]] || {
    echo "Error: OpenMPI not found at ${OPENMPI_DIR}" >&2
    return 1
  }
  [[ -d "${OPENBLAS_DIR}" ]] || {
    echo "Error: OpenBLAS not found at ${OPENBLAS_DIR}" >&2
    return 1
  }
}

# Create source directory
#
# Exit codes:
#   0 - Success
#   1 - Failed to create directories
create_directories() {
  mkdir -p "${SRC_DIR}" || {
    echo "Error: Failed to create directories" >&2
    return 1
  }
}

# Clone Dalton repository and determine version
#
# Exit codes:
#   0 - Success or already cloned
#   1 - Clone failed
clone_repository() {
  local temp_src="${TEMP_SOURCE_DIR}"
  local archive="${SRC_DIR}/dalton-${VERSION}.tar.gz"

  if [[ ! -d "${temp_src}" ]]; then
    if [[ -f "${archive}" ]]; then
      echo "Using existing archive: dalton-${VERSION}.tar.gz"
      tar -xf "${archive}" -C "${SRC_DIR}" || {
        echo "Error: Extraction failed" >&2
        return 1
      }
    else
      echo "Cloning Dalton ${GIT_REF}..."
      git clone --recursive --branch "${GIT_REF}" \
        https://gitlab.com/dalton/dalton.git "${temp_src}" || {
        echo "Error: Clone failed" >&2
        return 1
      }
    fi
  fi

  if [[ "${IS_DEV}" == "true" ]]; then
    local actual_version
    actual_version=$(determine_dev_version "${temp_src}")
    PATH_VERSION="${actual_version}"
    SOURCE_DIR="${SRC_DIR}/dalton-${PATH_VERSION}"
    if [[ "${temp_src}" != "${SOURCE_DIR}" ]] && [[ -d "${temp_src}" ]]; then
      mv "${temp_src}" "${SOURCE_DIR}"
    fi
    BUILD_DIR="${HOME}/software/build/dalton/${PATH_VERSION}-${PRECISION}"
  else
    SOURCE_DIR="${SRC_DIR}/dalton-${PATH_VERSION}"
    if [[ "${temp_src}" != "${SOURCE_DIR}" ]] && [[ -d "${temp_src}" ]]; then
      mv "${temp_src}" "${SOURCE_DIR}"
    fi
    BUILD_DIR="${HOME}/software/build/dalton/${PATH_VERSION}-${PRECISION}"
  fi

  mkdir -p "${BUILD_DIR}" || {
    echo "Error: Failed to create BUILD_DIR" >&2
    return 1
  }
}

# Configure Dalton build with MPI and BLAS/LAPACK
#
# Exit codes:
#   0 - Success
#   1 - Configuration failed
configure_build() {
  cd "${SOURCE_DIR}" || return 1

  local setup_dir
  setup_dir="${BUILD_DIR}"

  echo "Configuring Dalton..."
  ./setup --mpi \
    --fc "${OPENMPI_DIR}/bin/mpif90" \
    --cc "${OPENMPI_DIR}/bin/mpicc" \
    --cxx "${OPENMPI_DIR}/bin/mpicxx" \
    --blas "${OPENBLAS_DIR}/lib/libopenblas.so" \
    --lapack "${OPENBLAS_DIR}/lib/libopenblas.so" \
    "${setup_dir}" || {
    echo "Error: Setup failed" >&2
    return 1
  }
}

# Build Dalton from source
#
# Exit codes:
#   0 - Success
#   1 - Build failed
build_project() {
  cd "${BUILD_DIR}" || return 1

  echo "Building Dalton..."
  make -j "$(nproc)" || {
    echo "Error: Build failed" >&2
    return 1
  }
}

# Create default symlink to installed version
#
# Exit codes:
#   0 - Success
#   1 - Failed to create symlink
setup_symlink() {
  local default_link="${HOME}/software/build/dalton/default"

  rm -f "${default_link}"
  ln -sfn "${PATH_VERSION}-${PRECISION}" "${default_link}" || {
    echo "Error: Failed to create symlink" >&2
    return 1
  }
}

# Create source archive and remove source directory
#
# Exit codes:
#   0 - Always succeeds (cleanup warnings non-fatal)
archive_source() {
  local archive="${SRC_DIR}/dalton-${PATH_VERSION}.tar.gz"

  echo "Creating source archive..."
  tar -czf "${archive}" -C "${SRC_DIR}" "dalton-${PATH_VERSION}" || {
    echo "Warning: Failed to create archive" >&2
  }

  echo "Removing source directory..."
  rm -rf "${SOURCE_DIR}" || {
    echo "Warning: Failed to remove source directory" >&2
  }
}

# Verify Dalton build directory exists
#
# Exit codes:
#   0 - Success
#   1 - Verification failed
verify_installation() {
  [[ -d "${BUILD_DIR}" ]] || {
    echo "Error: Build directory not found" >&2
    return 1
  }
  echo "Installed to: ${BUILD_DIR}"
}

main() {
  validate_parameters || return 1
  validate_dependencies || return 1
  create_directories || return 1
  clone_repository || return 1
  configure_build || return 1
  build_project || return 1
  archive_source || return 1
  setup_symlink || return 1
  verify_installation
}

main "$@"
