#!/usr/bin/env bash
# Build and install NWChem from source with MPI and BLAS support.
#
# Usage: install-nwchem.sh [VERSION] [SYMLINK_NAME] [OPTIONS]
#
# Arguments:
#   VERSION      - Release version or git ref (e.g., 7.3.0, release-7-3-0, main)
#                  (default: 7.3.0)
#   SYMLINK_NAME - Name for symlink (default: default)
#
# Options:
#   --serial                    - Build without MPI (serial only)
#   --openmpi-version VERSION   - Use specific OpenMPI version (default: uses ~/software/build/openmpi/default)
#
# Examples:
#   ./install-nwchem.sh                              # MPI build with default OpenMPI
#   ./install-nwchem.sh --serial                     # Serial-only build
#   ./install-nwchem.sh 7.2.2 --openmpi-version 4.1.5
#
# Paths:
#   Source: ~/software/src/external
#   Build:  ~/software/build/nwchem/VERSION
#   Dependencies:
#     OpenMPI: ~/software/build/openmpi/default (or --openmpi-version)
#     OpenBLAS: ~/software/build/openblas/default

set -euo pipefail

readonly SRC_DIR="${HOME}/software/src/external"
readonly OPENMPI_HOME="${HOME}/software/build/openmpi"
readonly OPENBLAS_HOME="${HOME}/software/build/openblas"

VERSION="7.3.0"
SYMLINK_NAME="default"
OPENMPI_VERSION="default"
ENABLE_MPI=true
GIT_REF=""
IS_DEV=false
PATH_VERSION=""
TEMP_SOURCE_DIR=""
SOURCE_DIR=""
BUILD_DIR=""

# Parse command line arguments
#
# Exit codes:
#   0 - Arguments parsed successfully
#   1 - Invalid arguments
parse_arguments() {
  local arg_count=0
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
        arg_count=$((arg_count + 1))
        if [[ ${arg_count} -eq 1 ]]; then
          VERSION="$1"
        elif [[ ${arg_count} -eq 2 ]]; then
          SYMLINK_NAME="$1"
        else
          echo "Error: Unexpected argument: $1" >&2
          return 1
        fi
        shift
        ;;
    esac
  done

  # Set up derived variables
  GIT_REF="release-${VERSION//./-}"
  TEMP_SOURCE_DIR="${SRC_DIR}/nwchem-${VERSION}"

  if [[ "${VERSION}" =~ ^[0-9] ]]; then
    IS_DEV=false
    PATH_VERSION="${VERSION}"
  else
    IS_DEV=true
    PATH_VERSION=""
  fi

  SOURCE_DIR="${TEMP_SOURCE_DIR}"
}

# Extract version string from repository files
#
# Exit codes:
#   0 - Version extracted successfully
#   1 - Version not found
extract_version_from_repo() {
  local repo_dir="$1"

  if [[ -f "${repo_dir}/CMakeLists.txt" ]]; then
    grep -oP "VERSION\s+\K[^ \)]*" "${repo_dir}/CMakeLists.txt" | head -1 | tr -d ' \n'
    return 0
  fi

  if [[ -f "${repo_dir}/src/nwchem.F90" ]]; then
    grep -oP "program_version\s*=\s*['\"]?\K[^'\"]*" "${repo_dir}/src/nwchem.F90" | head -1 | tr -d ' \n'
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

# Verify required build tools and dependencies are available
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

# Clone NWChem repository and determine version
#
# Exit codes:
#   0 - Success or already cloned
#   1 - Clone failed
clone_repository() {
  local temp_src="${TEMP_SOURCE_DIR}"
  local archive="${SRC_DIR}/nwchem-${VERSION}.tar.gz"

  if [[ ! -d "${temp_src}" ]]; then
    if [[ -f "${archive}" ]]; then
      echo "Using existing archive: nwchem-${VERSION}.tar.gz"
      tar -xf "${archive}" -C "${SRC_DIR}" || {
        echo "Error: Extraction failed" >&2
        return 1
      }
    else
      echo "Cloning NWChem ${GIT_REF}..."
      git clone --depth 1 --branch "${GIT_REF}" \
        https://github.com/nwchemgit/nwchem.git "${temp_src}" || {
        echo "Error: Clone failed" >&2
        return 1
      }
    fi
  fi

  if [[ "${IS_DEV}" == "true" ]]; then
    local actual_version
    actual_version=$(determine_dev_version "${temp_src}")
    PATH_VERSION="${actual_version}"
    SOURCE_DIR="${SRC_DIR}/nwchem-${PATH_VERSION}"
    if [[ "${temp_src}" != "${SOURCE_DIR}" ]] && [[ -d "${temp_src}" ]]; then
      mv "${temp_src}" "${SOURCE_DIR}"
    fi
    BUILD_DIR="${HOME}/software/build/nwchem/${PATH_VERSION}"
  else
    SOURCE_DIR="${SRC_DIR}/nwchem-${PATH_VERSION}"
    if [[ "${temp_src}" != "${SOURCE_DIR}" ]] && [[ -d "${temp_src}" ]]; then
      mv "${temp_src}" "${SOURCE_DIR}"
    fi
    BUILD_DIR="${HOME}/software/build/nwchem/${PATH_VERSION}"
  fi

  mkdir -p "${BUILD_DIR}" || {
    echo "Error: Failed to create BUILD_DIR" >&2
    return 1
  }
}

# Configure NWChem build environment with MPI and BLAS
#
# Exit codes:
#   0 - Success
#   1 - Configuration failed
configure_build() {
  cd "${SOURCE_DIR}/src" || return 1

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

  echo "Configuring NWChem..."
  echo "  MPI: $([ "${ENABLE_MPI}" == "true" ] && echo "enabled (${openmpi_dir})" || echo "disabled")"
  echo "  BLAS: ${openblas_dir}"

  export NWCHEM_TOP="${SOURCE_DIR}"
  export NWCHEM_TARGET="LINUX64"
  export NWCHEM_MODULES="all"

  if [[ "${ENABLE_MPI}" == "true" ]]; then
    export MPI_LOC="${openmpi_dir}"
    export MPI_INCLUDE="${openmpi_dir}/include"
    export MPI_LIB="${openmpi_dir}/lib"
  fi

  export BLAS_LOC="${openblas_dir}"
  export BLASOPT="-L${openblas_dir}/lib -lopenblas"

  make nwchem_config || {
    echo "Error: Configuration failed" >&2
    return 1
  }
}

# Compile NWChem from source with MPI and BLAS
#
# Exit codes:
#   0 - Success
#   1 - Compilation failed
compile_project() {
  cd "${SOURCE_DIR}/src" || return 1

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

  echo "Building NWChem..."

  export NWCHEM_TOP="${SOURCE_DIR}"
  export NWCHEM_TARGET="LINUX64"
  export NWCHEM_MODULES="all"

  if [[ "${ENABLE_MPI}" == "true" ]]; then
    export MPI_LOC="${openmpi_dir}"
    export MPI_INCLUDE="${openmpi_dir}/include"
    export MPI_LIB="${openmpi_dir}/lib"
  fi

  export BLAS_LOC="${openblas_dir}"
  export BLASOPT="-L${openblas_dir}/lib -lopenblas"

  make FC=gfortran -j "$(nproc)" || {
    echo "Error: Compilation failed" >&2
    return 1
  }
}

# Copy NWChem executable and data files to build directory
#
# Exit codes:
#   0 - Success
#   1 - Installation failed
install_executable() {
  echo "Installing NWChem to ${BUILD_DIR}..."

  local nwchem_bin="${SOURCE_DIR}/bin/LINUX64/nwchem"

  [[ -x "${nwchem_bin}" ]] || {
    echo "Error: NWChem executable not found at ${nwchem_bin}" >&2
    return 1
  }

  mkdir -p "${BUILD_DIR}/bin" || {
    echo "Error: Failed to create build bin directory" >&2
    return 1
  }

  cp "${nwchem_bin}" "${BUILD_DIR}/bin/" || {
    echo "Error: Failed to copy executable" >&2
    return 1
  }

  chmod +x "${BUILD_DIR}/bin/nwchem"

  # Copy data files if they exist
  if [[ -d "${SOURCE_DIR}/data" ]]; then
    mkdir -p "${BUILD_DIR}/data"
    cp -r "${SOURCE_DIR}/data"/* "${BUILD_DIR}/data/" || {
      echo "Warning: Failed to copy data files" >&2
    }
  fi
}

# Create default symlink to installed version
#
# Exit codes:
#   0 - Success
#   1 - Failed to create symlink
setup_symlink() {
  local default_link="${HOME}/software/build/nwchem/${SYMLINK_NAME}"

  rm -f "${default_link}"
  ln -sfn "${PATH_VERSION}" "${default_link}" || {
    echo "Error: Failed to create symlink" >&2
    return 1
  }
}

# Create source archive and remove source directory
#
# Exit codes:
#   0 - Always succeeds (cleanup warnings non-fatal)
archive_source() {
  local archive="${SRC_DIR}/nwchem-${PATH_VERSION}.tar.gz"

  echo "Creating source archive..."
  tar -czf "${archive}" -C "${SRC_DIR}" "nwchem-${PATH_VERSION}" || {
    echo "Warning: Failed to create archive" >&2
  }

  echo "Removing source directory..."
  rm -rf "${SOURCE_DIR}" || {
    echo "Warning: Failed to remove source directory" >&2
  }
}

# Verify NWChem executable was installed successfully
#
# Exit codes:
#   0 - Success
#   1 - Verification failed
verify_installation() {
  [[ -x "${BUILD_DIR}/bin/nwchem" ]] || {
    echo "Error: NWChem executable not found" >&2
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
  echo "NWChem Installation Complete"
  echo "=========================================="
  echo "Executable: ${BUILD_DIR}/bin/nwchem"
  echo ""
  echo "Build Configuration:"
  echo "  MPI: $([ "${ENABLE_MPI}" == "true" ] && echo "enabled (${openmpi_dir})" || echo "disabled (serial)")"
  echo "  BLAS: ${openblas_dir}"
  echo ""
  echo "Add to your shell profile:"
  echo "  export NWCHEM_HOME=${BUILD_DIR}"
  echo "  export PATH=\$PATH:\${NWCHEM_HOME}/bin"
  echo ""
  echo "Usage:"
  if [[ "${ENABLE_MPI}" == "true" ]]; then
    echo "  nwchem input.nw                        (serial)"
    echo "  mpirun -np 4 nwchem input.nw           (parallel, MPI enabled)"
  else
    echo "  nwchem input.nw                        (serial)"
  fi
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
