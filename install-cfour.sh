#!/usr/bin/env bash
# Install CFOUR from source with autotools and MPI support.
#
# Usage: install-cfour.sh [VERSION] [OPTIONS]
#
# Arguments:
#   VERSION - CFOUR version (default: 2.1)
#
# Options:
#   --serial                    - Build without MPI (serial only)
#   --openmpi-version VERSION   - Use specific OpenMPI version (default: uses ~/software/build/openmpi/default)
#
# Prerequisites:
#   Source archive must be placed at ~/software/src/external/cfour-VERSION.tar.gz
#   CFOUR requires a license agreement from https://cfour.uni-mainz.de/cfour/
#
# Paths:
#   Source: ~/software/src/external
#   Build:  ~/software/build/cfour/VERSION
#   Dependencies:
#     OpenMPI: ~/software/build/openmpi/default (or --openmpi-version)
#     OpenBLAS: ~/software/build/openblas/default

set -euo pipefail

readonly SRC_DIR="${HOME}/software/src/external"
readonly OPENMPI_HOME="${HOME}/software/build/openmpi"
readonly OPENBLAS_HOME="${HOME}/software/build/openblas"

VERSION="2.1"
OPENMPI_VERSION="default"
ENABLE_MPI=true
ARCHIVE=""
SOURCE_DIR=""
BUILD_DIR=""

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
        if [[ -z "${VERSION}" ]] || [[ "${VERSION}" == "2.1" ]]; then
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
  ARCHIVE="cfour-${VERSION}.tar.gz"
  SOURCE_DIR="${SRC_DIR}/cfour-${VERSION}"
  BUILD_DIR="${HOME}/software/build/cfour/${VERSION}"
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

# Verify source archive exists at expected location
#
# Exit codes:
#   0 - Source archive found
#   1 - Source archive not found
validate_source_exists() {
  [[ -f "${SRC_DIR}/${ARCHIVE}" ]] || {
    echo "Error: Source archive not found" >&2
    echo "Required at: ${SRC_DIR}/${ARCHIVE}" >&2
    echo "Download from: https://cfour.uni-mainz.de/cfour/" >&2
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

# Verify required build tools are available
#
# Exit codes:
#   0 - All dependencies found
#   1 - Missing dependencies
check_dependencies() {
  command -v gfortran >/dev/null || {
    echo "Error: gfortran not found in PATH" >&2
    return 1
  }
  command -v gcc >/dev/null || {
    echo "Error: gcc not found in PATH" >&2
    return 1
  }
  command -v make >/dev/null || {
    echo "Error: make not found in PATH" >&2
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

# Extract CFOUR source archive
#
# Exit codes:
#   0 - Success or already extracted
#   1 - Extraction failed
download_and_extract() {
  if [[ ! -d "${SOURCE_DIR}" ]]; then
    if [[ ! -f "${SRC_DIR}/${ARCHIVE}" ]]; then
      echo "Error: Source archive not found at ${SRC_DIR}/${ARCHIVE}" >&2
      echo "CFOUR source must be pre-placed at: ${SRC_DIR}/${ARCHIVE}" >&2
      return 1
    fi
    echo "Extracting CFOUR ${VERSION}..."
    tar -xf "${SRC_DIR}/${ARCHIVE}" -C "${SRC_DIR}" || {
      echo "Error: Extraction failed" >&2
      return 1
    }
  fi
}

# Configure CFOUR build with autotools
#
# Exit codes:
#   0 - Success
#   1 - Configuration failed
configure_build() {
  cd "${SOURCE_DIR}" || return 1

  local openmpi_dir
  local openblas_dir
  local configure_args=""

  openblas_dir="${OPENBLAS_HOME}/default"

  if [[ "${ENABLE_MPI}" == "true" ]]; then
    if [[ "${OPENMPI_VERSION}" == "default" ]]; then
      openmpi_dir="${OPENMPI_HOME}/default"
    else
      openmpi_dir="${OPENMPI_HOME}/${OPENMPI_VERSION}-lp64"
    fi
  fi

  echo "Configuring CFOUR with autotools..."
  echo "  MPI: $([ "${ENABLE_MPI}" == "true" ] && echo "enabled (${openmpi_dir})" || echo "disabled")"
  echo "  BLAS: ${openblas_dir}"

  configure_args="--prefix=${BUILD_DIR}"

  if [[ "${ENABLE_MPI}" == "true" ]]; then
    configure_args="${configure_args} --enable-mpi MPI_HOME=${openmpi_dir}"
    export LDFLAGS="-L${openmpi_dir}/lib"
    export CPPFLAGS="-I${openmpi_dir}/include"
  fi

  export LDFLAGS="${LDFLAGS:-} -L${openblas_dir}/lib"
  export CPPFLAGS="${CPPFLAGS:-} -I${openblas_dir}/include"
  export LIBS="-lopenblas"

  ./configure ${configure_args} || {
    echo "Error: Configure failed" >&2
    return 1
  }
}

# Compile CFOUR from source
#
# Exit codes:
#   0 - Success
#   1 - Compilation failed
compile_project() {
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

  echo "Building CFOUR..."

  if [[ "${ENABLE_MPI}" == "true" ]]; then
    export LDFLAGS="-L${openmpi_dir}/lib"
    export CPPFLAGS="-I${openmpi_dir}/include"
  fi

  export LDFLAGS="${LDFLAGS:-} -L${openblas_dir}/lib"
  export CPPFLAGS="${CPPFLAGS:-} -I${openblas_dir}/include"
  export LIBS="-lopenblas"

  make || {
    echo "Error: Compilation failed" >&2
    return 1
  }
}

# Install CFOUR to build directory
#
# Exit codes:
#   0 - Success
#   1 - Installation failed
install_project() {
  cd "${SOURCE_DIR}" || return 1

  echo "Installing CFOUR..."
  make install || {
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
  local default_link="${HOME}/software/build/cfour/default"

  rm -f "${default_link}"
  ln -sfn "${VERSION}" "${default_link}" || {
    echo "Error: Failed to create symlink" >&2
    return 1
  }
}

# Create source archive and remove source directory
#
# Exit codes:
#   0 - Always succeeds (cleanup warnings non-fatal)
cleanup_source() {
  local archive="${SRC_DIR}/cfour-${VERSION}.tar.gz"

  echo "Creating source archive..."
  tar -czf "${archive}" -C "${SRC_DIR}" "cfour-${VERSION}" || {
    echo "Warning: Failed to create archive" >&2
  }

  echo "Removing source directory..."
  rm -rf "${SOURCE_DIR}" || {
    echo "Warning: Failed to remove source directory" >&2
  }
}

# Verify CFOUR executable was installed successfully
#
# Exit codes:
#   0 - Success
#   1 - Verification failed
verify_installation() {
  [[ -x "${BUILD_DIR}/bin/xcfour" ]] || {
    echo "Error: CFOUR executable not found" >&2
    return 1
  }
  echo "Installed to: ${BUILD_DIR}"
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
  echo "CFOUR Installation Complete"
  echo "=========================================="
  echo "Executable: ${BUILD_DIR}/bin/xcfour"
  echo ""
  echo "Build Configuration:"
  echo "  MPI: $([ "${ENABLE_MPI}" == "true" ] && echo "enabled (${openmpi_dir})" || echo "disabled (serial)")"
  echo "  BLAS: ${openblas_dir}"
  echo ""
  echo "Add to your shell profile:"
  echo "  export CFOUR_HOME=${BUILD_DIR}"
  echo "  export PATH=\$PATH:\${CFOUR_HOME}/bin"
  echo "=========================================="
  echo ""
}

main() {
  parse_arguments "$@" || return 1
  validate_parameters || return 1
  validate_source_exists || return 1
  check_dependencies || return 1
  create_directories || return 1
  download_and_extract || return 1
  configure_build || return 1
  compile_project || return 1
  install_project || return 1
  cleanup_source || return 1
  setup_symlink || return 1
  verify_installation || return 1
  print_setup
}

main "$@"
