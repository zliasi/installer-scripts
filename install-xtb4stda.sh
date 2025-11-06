#!/usr/bin/env bash
# Build and install xtb4stda from source with Intel oneAPI Fortran and Make.
#
# Usage: install-xtb4stda.sh [VERSION] [SYMLINK_NAME]
#
# Arguments:
#   VERSION      - Release version (e.g., 1.1.1) (default: 1.1.1)
#   SYMLINK_NAME - Name for symlink (default: default)
#
# Notes:
#   xtb4stda uses Make build system with Intel Fortran (ifx)
#   Prepares ground state calculations with sTDA-xTB for std2
#   Requires Intel oneAPI 2024+ to be installed at /software/kemi/intel/oneapi
#   Requires ruby for build scripts
#
# Paths:
#   Source: ~/software/src/external
#   Build:  ~/software/build/xtb4stda/VERSION
#   Intel oneAPI: /software/kemi/intel/oneapi

set -euo pipefail

# Source Intel oneAPI environment early so it persists throughout script execution
set +u
source /software/kemi/intel/oneapi/setvars.sh --force >/dev/null 2>&1 || true
set -u

readonly SRC_DIR="${HOME}/software/src/external"
readonly BUILD_BASE_DIR="${HOME}/software/build"

VERSION="${1:-1.1.1}"
SYMLINK_NAME="${2:-default}"
GIT_REF="v${VERSION#v}"
TEMP_SOURCE_DIR="${SRC_DIR}/xtb4stda-${VERSION}"
IS_DEV=false
PATH_VERSION=""

if [[ "${VERSION}" =~ ^[0-9] ]]; then
  IS_DEV=false
  PATH_VERSION="${VERSION}"
else
  IS_DEV=true
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

  if [[ -f "${repo_dir}/setup.py" ]]; then
    grep -oP "version\s*=\s*['\"]?\K[^'\"]*" "${repo_dir}/setup.py" | head -1 | tr -d ' \n'
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
}

# Verify required build tools are available
#
# Exit codes:
#   0 - All dependencies found
#   1 - Missing dependencies
check_dependencies() {
  [[ -f "/software/kemi/intel/oneapi/setvars.sh" ]] || {
    echo "Error: Intel oneAPI not found at /software/kemi/intel/oneapi" >&2
    return 1
  }
  command -v make >/dev/null || {
    echo "Error: make not found in PATH" >&2
    return 1
  }
  command -v ruby >/dev/null || {
    echo "Error: ruby not found in PATH" >&2
    return 1
  }
  command -v git >/dev/null || {
    echo "Error: git not found in PATH" >&2
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

# Clone xtb4stda repository and determine version
#
# Exit codes:
#   0 - Success or already cloned
#   1 - Clone failed
clone_repository() {
  local temp_src="${TEMP_SOURCE_DIR}"
  local archive="${SRC_DIR}/xtb4stda-${VERSION}.tar.gz"

  if [[ ! -d "${temp_src}" ]]; then
    if [[ -f "${archive}" ]]; then
      echo "Using existing archive: xtb4stda-${VERSION}.tar.gz"
      tar -xf "${archive}" -C "${SRC_DIR}" || {
        echo "Error: Extraction failed" >&2
        return 1
      }
    else
      echo "Cloning xtb4stda ${GIT_REF}..."
      git clone --branch "${GIT_REF}" \
        https://github.com/grimme-lab/xtb4stda.git "${temp_src}" || {
        echo "Error: Clone failed" >&2
        return 1
      }
    fi
  fi

  if [[ "${IS_DEV}" == "true" ]]; then
    local actual_version
    actual_version=$(determine_dev_version "${temp_src}")
    PATH_VERSION="${actual_version}"
    SOURCE_DIR="${SRC_DIR}/xtb4stda-${PATH_VERSION}"
    if [[ "${temp_src}" != "${SOURCE_DIR}" ]] && [[ -d "${temp_src}" ]]; then
      mv "${temp_src}" "${SOURCE_DIR}"
    fi
    BUILD_DIR="${BUILD_BASE_DIR}/xtb4stda/${PATH_VERSION}"
    BUILD_SUBDIR="${BUILD_DIR}/build"
  else
    SOURCE_DIR="${SRC_DIR}/xtb4stda-${PATH_VERSION}"
    if [[ "${temp_src}" != "${SOURCE_DIR}" ]] && [[ -d "${temp_src}" ]]; then
      mv "${temp_src}" "${SOURCE_DIR}"
    fi
    BUILD_DIR="${BUILD_BASE_DIR}/xtb4stda/${PATH_VERSION}"
    BUILD_SUBDIR="${BUILD_DIR}/build"
  fi

  mkdir -p "${BUILD_DIR}" || {
    echo "Error: Failed to create BUILD_DIR" >&2
    return 1
  }
}

# Configure xtb4stda build
#
# Exit codes:
#   0 - Success
#   1 - Configuration failed
configure_build() {
  cd "${SOURCE_DIR}" || return 1

  echo "Configuring xtb4stda with Make and Intel Fortran..."
}

# Compile xtb4stda from source
#
# Exit codes:
#   0 - Success
#   1 - Compilation failed
compile_project() {
  cd "${SOURCE_DIR}" || return 1

  echo "Building xtb4stda with Make and Intel Fortran..."

  echo "Note: Using serial compilation due to Fortran module dependencies"
  make FC=ifx CC=icx || {
    echo "Error: Compilation failed" >&2
    return 1
  }
}

# Install xtb4stda executable
#
# Exit codes:
#   0 - Success
#   1 - Installation failed
install_executable() {
  cd "${SOURCE_DIR}" || return 1

  echo "Installing xtb4stda to ${BUILD_DIR}..."

  # Create bin directory
  mkdir -p "${BUILD_DIR}/bin" || {
    echo "Error: Failed to create bin directory" >&2
    return 1
  }

  # Copy executable to installation directory
  if [[ -f "${SOURCE_DIR}/exe/xtb4stda" ]]; then
    cp "${SOURCE_DIR}/exe/xtb4stda" "${BUILD_DIR}/bin/xtb4stda" || {
      echo "Error: Failed to copy xtb4stda executable" >&2
      return 1
    }
  else
    echo "Error: xtb4stda executable not found at ${SOURCE_DIR}/exe/xtb4stda" >&2
    return 1
  fi
}

# Create default symlink to installed version
#
# Exit codes:
#   0 - Success
#   1 - Failed to create symlink
setup_symlink() {
  local symlink_dir
  symlink_dir="$(dirname "${BUILD_DIR}")"
  local symlink_path="${symlink_dir}/${SYMLINK_NAME}"

  rm -f "${symlink_path}"
  ln -sfn "${PATH_VERSION}" "${symlink_path}" || {
    echo "Error: Failed to create symlink" >&2
    return 1
  }
}

# Verify xtb4stda executable was installed successfully
#
# Exit codes:
#   0 - Success
#   1 - Verification failed
verify_installation() {
  [[ -x "${BUILD_DIR}/bin/xtb4stda" ]] || {
    echo "Error: xtb4stda executable not found" >&2
    return 1
  }
  echo "Installed to: ${BUILD_DIR}"
}

# Create source archive and remove source directory
#
# Exit codes:
#   0 - Always succeeds (cleanup warnings non-fatal)
archive_source() {
  local archive="${SRC_DIR}/xtb4stda-${PATH_VERSION}.tar.gz"

  echo "Creating source archive..."
  tar -czf "${archive}" -C "${SRC_DIR}" "xtb4stda-${PATH_VERSION}" || {
    echo "Warning: Failed to create archive" >&2
  }

  echo "Removing source directory..."
  rm -rf "${SOURCE_DIR}" || {
    echo "Warning: Failed to remove source directory" >&2
  }
}

# Generate file documenting external dependencies
#
# Exit codes:
#   0 - Always succeeds (file generation non-fatal)
generate_dependencies_file() {
  local deps_file="${BUILD_DIR}/DEPENDENCIES.txt"

  cat > "${deps_file}" <<'DEPS'
=== External Dependencies for xtb4stda ===

Required external software/modules (must be sourced in submit scripts):

1. Intel oneAPI
   Version: 2024.0 or later
   Location: /software/kemi/intel/oneapi
   Components:
     - ifx: Intel Fortran compiler (LLVM-based)
     - icx: Intel C compiler
     - icpx: Intel C++ compiler
   Purpose: Provides Fortran and C/C++ compilers for xtb4stda
   Required for: Building and running xtb4stda

=== Usage in HPC Submit Scripts ===

Intel oneAPI must be sourced before running xtb4stda:

Example bash submit script for xtb4stda:
  #!/bin/bash
  source /software/kemi/intel/oneapi/setvars.sh --force

  export XTB4STDAHOME=~/software/build/xtb4stda/default
  export PATH=$PATH:${XTB4STDAHOME}/bin

  # Set threading for parallel computation
  export OMP_NUM_THREADS=8
  export MKL_NUM_THREADS=8

  xtb4stda coord > gs.stda-xtb.out

Example SLURM job submission with Intel oneAPI:
  #!/bin/bash
  #SBATCH --job-name=xtb4stda_calc
  #SBATCH --partition=cpu
  #SBATCH --cpus-per-task=8

  source /software/kemi/intel/oneapi/setvars.sh --force

  export XTB4STDAHOME=~/software/build/xtb4stda/default
  export PATH=$PATH:${XTB4STDAHOME}/bin
  export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
  export MKL_NUM_THREADS=$SLURM_CPUS_PER_TASK

  ${XTB4STDAHOME}/bin/xtb4stda coord > gs.stda-xtb.out

DEPS
  if [[ $? -ne 0 ]]; then
    echo "Warning: Failed to write dependencies file" >&2
  fi

  echo "Dependencies file created: ${deps_file}"
}

# Display installation instructions
#
# Exit codes:
#   0 - Always succeeds
print_setup() {
  echo ""
  echo "=========================================="
  echo "xtb4stda Installation Complete"
  echo "=========================================="
  echo "Executable: ${BUILD_DIR}/bin/xtb4stda"
  echo "Dependencies: ${BUILD_DIR}/DEPENDENCIES.txt"
  echo ""
  echo "Add to your shell profile:"
  echo "  export XTB4STDAHOME=${BUILD_DIR}"
  echo "  export PATH=\$PATH:\${XTB4STDAHOME}/bin"
  echo ""
  echo "Set threading for parallel computation:"
  echo "  export OMP_NUM_THREADS=<ncores>"
  echo "  export MKL_NUM_THREADS=<ncores>"
  echo ""
  echo "See ${BUILD_DIR}/DEPENDENCIES.txt for HPC submit script setup"
  echo "=========================================="
  echo ""
}

main() {
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
  generate_dependencies_file
  print_setup
}

main "$@"
