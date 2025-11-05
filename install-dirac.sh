#!/usr/bin/env bash
# Build and install DIRAC from source with CMake and MPI support.
#
# Usage: install-dirac.sh [VERSION] [OPTIONS]
#
# Arguments:
#   VERSION - Release version (e.g., 25.0) (default: 25.0)
#
# Options:
#   --serial                    - Build without MPI (serial only)
#   --openmpi-version VERSION   - Use specific OpenMPI version (default: uses ~/software/build/openmpi/default)
#
# Paths:
#   Source: ~/software/src/external
#   Build:  ~/software/build/dirac/VERSION
#   Dependencies:
#     OpenMPI: ~/software/build/openmpi/default (or --openmpi-version)
#     OpenBLAS: ~/software/build/openblas/default

set -euo pipefail

readonly SRC_DIR="${HOME}/software/src/external"
readonly OPENMPI_HOME="${HOME}/software/build/openmpi"
readonly OPENBLAS_HOME="${HOME}/software/build/openblas"

VERSION="25.0"
OPENMPI_VERSION="default"
ENABLE_MPI=true
GIT_REF=""
TEMP_SOURCE_DIR=""

if [[ "${VERSION}" =~ ^[0-9] ]]; then
  readonly IS_DEV=false
  PATH_VERSION="${VERSION}"
else
  readonly IS_DEV=true
  PATH_VERSION=""
fi

SOURCE_DIR="${TEMP_SOURCE_DIR}"
BUILD_DIR=""
BUILD_SUBDIR=""

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

  if [[ -f "${repo_dir}/CMakeLists.txt" ]]; then
    grep -oP "VERSION\s+\K[^ \)]*" "${repo_dir}/CMakeLists.txt" | head -1 | tr -d ' \n'
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

# Parse command line arguments
#
# Exit codes:
#   0 - Arguments parsed successfully
#   1 - Invalid arguments
parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --serial)
        ENABLE_MPI=false
        shift
        ;;
      --openmpi-version)
        OPENMPI_VERSION="$2"
        shift 2
        ;;
      --*)
        echo "Error: Unknown option: $1" >&2
        return 1
        ;;
      *)
        if [[ -z "${VERSION}" ]] || [[ "${VERSION}" == "25.0" ]]; then
          VERSION="$1"
        else
          echo "Error: Unexpected argument: $1" >&2
          return 1
        fi
        shift
        ;;
    esac
  done

  # Set up derived variables
  GIT_REF="v${VERSION#v}"
  TEMP_SOURCE_DIR="${SRC_DIR}/dirac-${VERSION}"

  if [[ "${VERSION}" =~ ^[0-9] ]]; then
    IS_DEV=false
    PATH_VERSION="${VERSION}"
  else
    IS_DEV=true
    PATH_VERSION=""
  fi

  SOURCE_DIR="${TEMP_SOURCE_DIR}"
}

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

# Verify required build tools are available
#
# Exit codes:
#   0 - All dependencies found
#   1 - Missing dependencies
check_dependencies() {
  command -v cmake >/dev/null || {
    echo "Error: cmake not found in PATH" >&2
    return 1
  }
  command -v gfortran >/dev/null || {
    echo "Error: gfortran not found in PATH" >&2
    return 1
  }
  command -v git >/dev/null || {
    echo "Error: git not found in PATH" >&2
    return 1
  }

  local openmpi_dir
  local openblas_dir

  if [[ "${ENABLE_MPI}" == "true" ]]; then
    if [[ "${OPENMPI_VERSION}" == "default" ]]; then
      openmpi_dir="${OPENMPI_HOME}/default"
    else
      openmpi_dir="${OPENMPI_HOME}/${OPENMPI_VERSION}-lp64"
    fi

    [[ -d "${openmpi_dir}" ]] || {
      echo "Error: OpenMPI not found at ${openmpi_dir}" >&2
      echo "Install with: ./install-openmpi.sh ${OPENMPI_VERSION}" >&2
      return 1
    }
  fi

  openblas_dir="${OPENBLAS_HOME}/default"
  [[ -d "${openblas_dir}" ]] || {
    echo "Error: OpenBLAS not found at ${openblas_dir}" >&2
    echo "Install with: ./install-openblas.sh" >&2
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

# Clone DIRAC repository and determine version
#
# Exit codes:
#   0 - Success or already cloned
#   1 - Clone failed
clone_repository() {
  local temp_src="${TEMP_SOURCE_DIR}"
  local archive="${SRC_DIR}/dirac-${VERSION}.tar.gz"

  if [[ ! -d "${temp_src}" ]]; then
    if [[ -f "${archive}" ]]; then
      echo "Using existing archive: dirac-${VERSION}.tar.gz"
      tar -xf "${archive}" -C "${SRC_DIR}" || {
        echo "Error: Extraction failed" >&2
        return 1
      }
    else
      echo "Cloning DIRAC ${GIT_REF}..."
      git clone --recursive --branch "${GIT_REF}" \
        https://gitlab.com/dirac/dirac.git "${temp_src}" || {
        echo "Error: Clone failed" >&2
        return 1
      }
    fi
  fi

  if [[ "${IS_DEV}" == "true" ]]; then
    local actual_version
    actual_version=$(determine_dev_version "${temp_src}")
    PATH_VERSION="${actual_version}"
    SOURCE_DIR="${SRC_DIR}/dirac-${PATH_VERSION}"
    if [[ "${temp_src}" != "${SOURCE_DIR}" ]] && [[ -d "${temp_src}" ]]; then
      mv "${temp_src}" "${SOURCE_DIR}"
    fi
    BUILD_DIR="${HOME}/software/build/dirac/${PATH_VERSION}"
    BUILD_SUBDIR="${BUILD_DIR}/build"
  else
    SOURCE_DIR="${SRC_DIR}/dirac-${PATH_VERSION}"
    if [[ "${temp_src}" != "${SOURCE_DIR}" ]] && [[ -d "${temp_src}" ]]; then
      mv "${temp_src}" "${SOURCE_DIR}"
    fi
    BUILD_DIR="${HOME}/software/build/dirac/${PATH_VERSION}"
    BUILD_SUBDIR="${BUILD_DIR}/build"
  fi

  mkdir -p "${BUILD_DIR}" || {
    echo "Error: Failed to create BUILD_DIR" >&2
    return 1
  }
}

# Configure DIRAC build with setup script
#
# Exit codes:
#   0 - Success
#   1 - Configuration failed
configure_build() {
  cd "${SOURCE_DIR}" || return 1

  local openmpi_dir
  local openblas_dir

  openblas_dir="${OPENBLAS_HOME}/default"

  if [[ "${ENABLE_MPI}" == "true" ]]; then
    if [[ "${OPENMPI_VERSION}" == "default" ]]; then
      openmpi_dir="${OPENMPI_HOME}/default"
    else
      openmpi_dir="${OPENMPI_HOME}/${OPENMPI_VERSION}-lp64"
    fi
  fi

  echo "Configuring DIRAC with setup..."
  echo "  MPI: $([ "${ENABLE_MPI}" == "true" ] && echo "enabled (${openmpi_dir})" || echo "disabled")"
  echo "  BLAS: ${openblas_dir}"

  if [[ "${ENABLE_MPI}" == "true" ]]; then
    export MPI_LOC="${openmpi_dir}"
    export MPI_INCLUDE="${openmpi_dir}/include"
    export MPI_LIB="${openmpi_dir}/lib"
  fi

  export BLAS_LOC="${openblas_dir}"
  export BLASOPT="-L${openblas_dir}/lib -lopenblas"

  ./setup "${BUILD_SUBDIR}" || {
    echo "Error: Setup failed" >&2
    return 1
  }
}

# Compile DIRAC from source
#
# Exit codes:
#   0 - Success
#   1 - Compilation failed
compile_project() {
  cd "${BUILD_SUBDIR}" || return 1

  local openmpi_dir
  local openblas_dir

  openblas_dir="${OPENBLAS_HOME}/default"

  if [[ "${ENABLE_MPI}" == "true" ]]; then
    if [[ "${OPENMPI_VERSION}" == "default" ]]; then
      openmpi_dir="${OPENMPI_HOME}/default"
    else
      openmpi_dir="${OPENMPI_HOME}/${OPENMPI_VERSION}-lp64"
    fi
  fi

  echo "Building DIRAC..."

  if [[ "${ENABLE_MPI}" == "true" ]]; then
    export MPI_LOC="${openmpi_dir}"
    export MPI_INCLUDE="${openmpi_dir}/include"
    export MPI_LIB="${openmpi_dir}/lib"
  fi

  export BLAS_LOC="${openblas_dir}"
  export BLASOPT="-L${openblas_dir}/lib -lopenblas"

  make -j || {
    echo "Error: Build failed" >&2
    return 1
  }
}

# Copy DIRAC executable to build directory
#
# Exit codes:
#   0 - Success
#   1 - Copy failed
install_executable() {
  echo "Copying executable to ${BUILD_DIR}..."
  if [[ -f "${BUILD_SUBDIR}/bin/dirac" ]]; then
    cp "${BUILD_SUBDIR}/bin/dirac" "${BUILD_DIR}/" || {
      echo "Error: Failed to copy executable" >&2
      return 1
    }
    chmod +x "${BUILD_DIR}/dirac"
  fi
}

# Create default symlink to installed version
#
# Exit codes:
#   0 - Success
#   1 - Failed to create symlink
setup_symlink() {
  local default_link="${HOME}/software/build/dirac/default"

  rm -f "${default_link}"
  ln -sfn "${PATH_VERSION}" "${default_link}" || {
    echo "Error: Failed to create symlink" >&2
    return 1
  }
}

# Verify DIRAC build directory exists
#
# Exit codes:
#   0 - Success
#   1 - Verification failed
verify_installation() {
  [[ -d "${BUILD_SUBDIR}" ]] || {
    echo "Error: Build directory not found" >&2
    return 1
  }
  echo "Installed to: ${BUILD_DIR}"
}

# Create source archive and remove source directory
#
# Exit codes:
#   0 - Always succeeds (cleanup warnings non-fatal)
archive_source() {
  local archive="${SRC_DIR}/dirac-${PATH_VERSION}.tar.gz"

  echo "Creating source archive..."
  tar -czf "${archive}" -C "${SRC_DIR}" "dirac-${PATH_VERSION}" || {
    echo "Warning: Failed to create archive" >&2
  }

  echo "Removing source directory..."
  rm -rf "${SOURCE_DIR}" || {
    echo "Warning: Failed to remove source directory" >&2
  }
}

# Display installation instructions
#
# Exit codes:
#   0 - Always succeeds
print_setup() {
  local openmpi_dir
  local openblas_dir

  openblas_dir="${OPENBLAS_HOME}/default"

  if [[ "${ENABLE_MPI}" == "true" ]]; then
    if [[ "${OPENMPI_VERSION}" == "default" ]]; then
      openmpi_dir="${OPENMPI_HOME}/default"
    else
      openmpi_dir="${OPENMPI_HOME}/${OPENMPI_VERSION}-lp64"
    fi
  fi

  echo ""
  echo "=========================================="
  echo "DIRAC Installation Complete"
  echo "=========================================="
  echo "Build directory: ${BUILD_DIR}"
  echo ""
  echo "Build Configuration:"
  echo "  MPI: $([ "${ENABLE_MPI}" == "true" ] && echo "enabled (${openmpi_dir})" || echo "disabled (serial)")"
  echo "  BLAS: ${openblas_dir}"
  echo ""
  echo "Add to your shell profile:"
  echo "  export DIRAC_HOME=${BUILD_DIR}"
  echo "  export PATH=\$PATH:\${DIRAC_HOME}/build/bin"
  echo "=========================================="
  echo ""
}

main() {
  parse_arguments "$@" || return 1
  validate_parameters || return 1
  check_dependencies || return 1
  create_directories || return 1
  clone_repository || return 1
  configure_build || return 1
  compile_project || return 1
  install_executable || return 1
  archive_source || return 1
  setup_symlink || return 1
  verify_installation || return 1
  print_setup
}

main "$@"
