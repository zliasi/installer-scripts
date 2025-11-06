#!/usr/bin/env bash
# Build and install std2 from source with Intel oneAPI Fortran and Make.
#
# Usage: install-std2.sh [VERSION] [SYMLINK_NAME]
#
# Arguments:
#   VERSION      - Release version (e.g., 2.0.1) (default: 2.0.1)
#   SYMLINK_NAME - Name for symlink (default: default)
#
# Notes:
#   std2 uses Make build system with Intel Fortran (ifx)
#   Downloads and builds libcint v6.1.2 during configuration
#   Requires Intel oneAPI 2024+ to be installed at /software/kemi/intel/oneapi
#   Requires cmake and wget for building libcint dependency
#
# Paths:
#   Source: ~/software/src/external
#   Build:  ~/software/build/std2/VERSION
#   Intel oneAPI: /software/kemi/intel/oneapi

set -euo pipefail

# Source Intel oneAPI environment early so it persists throughout script execution
set +u
source /software/kemi/intel/oneapi/setvars.sh --force >/dev/null 2>&1 || true
set -u

readonly SRC_DIR="${HOME}/software/src/external"
readonly BUILD_BASE_DIR="${HOME}/software/build"

VERSION="${1:-2.0.1}"
SYMLINK_NAME="${2:-default}"
GIT_REF="v${VERSION#v}"
TEMP_SOURCE_DIR="${SRC_DIR}/std2-${VERSION}"
IS_DEV=false
PATH_VERSION=""

# libcint version and paths
readonly LIBCINT_VERSION="6.1.2"
LIBCINT_BUILD_DIR="${BUILD_BASE_DIR}/libcint/${LIBCINT_VERSION}"

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
  command -v cmake >/dev/null || {
    echo "Error: cmake not found in PATH" >&2
    return 1
  }
  command -v wget >/dev/null || {
    echo "Error: wget not found in PATH" >&2
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

# Clone std2 repository and determine version
#
# Exit codes:
#   0 - Success or already cloned
#   1 - Clone failed
clone_repository() {
  local temp_src="${TEMP_SOURCE_DIR}"
  local archive="${SRC_DIR}/std2-${VERSION}.tar.gz"

  if [[ ! -d "${temp_src}" ]]; then
    if [[ -f "${archive}" ]]; then
      echo "Using existing archive: std2-${VERSION}.tar.gz"
      tar -xf "${archive}" -C "${SRC_DIR}" || {
        echo "Error: Extraction failed" >&2
        return 1
      }
    else
      echo "Cloning std2 ${GIT_REF}..."
      git clone --branch "${GIT_REF}" \
        https://github.com/grimme-lab/std2.git "${temp_src}" || {
        echo "Error: Clone failed" >&2
        return 1
      }
    fi
  fi

  if [[ "${IS_DEV}" == "true" ]]; then
    local actual_version
    actual_version=$(determine_dev_version "${temp_src}")
    PATH_VERSION="${actual_version}"
    SOURCE_DIR="${SRC_DIR}/std2-${PATH_VERSION}"
    if [[ "${temp_src}" != "${SOURCE_DIR}" ]] && [[ -d "${temp_src}" ]]; then
      mv "${temp_src}" "${SOURCE_DIR}"
    fi
    BUILD_DIR="${HOME}/software/build/std2/${PATH_VERSION}"
    BUILD_SUBDIR="${BUILD_DIR}/build"
  else
    SOURCE_DIR="${SRC_DIR}/std2-${PATH_VERSION}"
    if [[ "${temp_src}" != "${SOURCE_DIR}" ]] && [[ -d "${temp_src}" ]]; then
      mv "${temp_src}" "${SOURCE_DIR}"
    fi
    BUILD_DIR="${HOME}/software/build/std2/${PATH_VERSION}"
    BUILD_SUBDIR="${BUILD_DIR}/build"
  fi

  mkdir -p "${BUILD_DIR}" || {
    echo "Error: Failed to create BUILD_DIR" >&2
    return 1
  }
}

# Configure std2 build with Intel Fortran and Make
#
# Exit codes:
#   0 - Success
#   1 - Configuration failed
configure_build() {
  cd "${SOURCE_DIR}" || return 1

  echo "Configuring std2 with Make and Intel Fortran..."

  echo "Checking/downloading and building libcint..."
  if [[ ! -d "${LIBCINT_BUILD_DIR}" ]]; then
    if [[ ! -d "${SOURCE_DIR}/libcint" ]]; then
      echo "Downloading libcint v${LIBCINT_VERSION} from official release..."
      mkdir -p "${SOURCE_DIR}/libcint"
      cd "${SOURCE_DIR}/libcint" || return 1

      wget https://github.com/pierre-24/libcint-meson/releases/download/v0.3.0/libcint_v${LIBCINT_VERSION}.tar.gz -O libcint.tar.gz || {
        echo "Error: Failed to download libcint" >&2
        return 1
      }

      tar -xzf libcint.tar.gz || {
        echo "Error: Failed to extract libcint" >&2
        return 1
      }

      cd "${SOURCE_DIR}" || return 1
    fi

    echo "Building libcint with cmake to ${LIBCINT_BUILD_DIR}..."
    mkdir -p "${LIBCINT_BUILD_DIR}"

    set +u
    cmake -S "${SOURCE_DIR}/libcint" -B "${LIBCINT_BUILD_DIR}" || {
      echo "Error: libcint cmake configuration failed" >&2
      set -u
      return 1
    }
    cmake --build "${LIBCINT_BUILD_DIR}" || {
      echo "Error: libcint build failed" >&2
      set -u
      return 1
    }
    set -u

    # Create symlink from source directory to persistent build location
    echo "Creating symlink from source to persistent build location..."
    rm -f "${SOURCE_DIR}/libcint/build"
    ln -sfn "${LIBCINT_BUILD_DIR}" "${SOURCE_DIR}/libcint/build" || {
      echo "Warning: Failed to create symlink for libcint" >&2
    }
  fi
}

# Compile std2 from source
#
# Exit codes:
#   0 - Success
#   1 - Compilation failed
compile_project() {
  cd "${SOURCE_DIR}" || return 1

  echo "Building std2 with Make and Intel Fortran..."

  # Use both source and actual location to ensure linker finds libcint
  export LD_LIBRARY_PATH="${SOURCE_DIR}/libcint/build:${LIBCINT_BUILD_DIR}:${LD_LIBRARY_PATH:-}"

  echo "Note: Using serial compilation due to Fortran module dependencies"
  make PREFIX="${BUILD_DIR}" FC=ifx CC=icx || {
    echo "Error: Compilation failed" >&2
    return 1
  }
}

# Install std2 using Make install
#
# Exit codes:
#   0 - Success
#   1 - Installation failed
install_executable() {
  cd "${SOURCE_DIR}" || return 1

  echo "Installing std2 to ${BUILD_DIR}..."

  # Create bin directory
  mkdir -p "${BUILD_DIR}/bin" || {
    echo "Error: Failed to create bin directory" >&2
    return 1
  }

  # Copy executable to installation directory
  if [[ -f "${SOURCE_DIR}/std2" ]]; then
    cp "${SOURCE_DIR}/std2" "${BUILD_DIR}/bin/std2" || {
      echo "Error: Failed to copy std2 executable" >&2
      return 1
    }
  else
    echo "Error: std2 executable not found at ${SOURCE_DIR}/std2" >&2
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

# Verify std2 executable was installed successfully
#
# Exit codes:
#   0 - Success
#   1 - Verification failed
verify_installation() {
  [[ -x "${BUILD_DIR}/bin/std2" ]] || {
    echo "Error: std2 executable not found" >&2
    return 1
  }
  echo "Installed to: ${BUILD_DIR}"
}

# Create source archive and remove source directory
#
# Exit codes:
#   0 - Always succeeds (cleanup warnings non-fatal)
archive_source() {
  local archive="${SRC_DIR}/std2-${PATH_VERSION}.tar.gz"

  echo "Creating source archive..."
  tar -czf "${archive}" -C "${SRC_DIR}" "std2-${PATH_VERSION}" || {
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
=== External Dependencies for std2 ===

Required external software/modules (must be sourced in submit scripts):

1. Intel oneAPI
   Version: 2024.0 or later
   Location: /software/kemi/intel/oneapi
   Components:
     - ifx: Intel Fortran compiler (LLVM-based)
     - icx: Intel C compiler
     - icpx: Intel C++ compiler
   Purpose: Provides Fortran and C/C++ compilers for std2
   Required for: Building and running std2

2. libcint (integral computation library)
   Built separately and shared across all std2 versions
   Location: ~/software/build/libcint/6.1.2
   Purpose: Provides one- and two-electron integral computation
   Required for: Runtime execution of std2

=== Usage in HPC Submit Scripts ===

Intel oneAPI must be sourced before running std2. Additionally, libcint library path must be added to LD_LIBRARY_PATH:

Example bash submit script for std2:
  #!/bin/bash
  source /software/kemi/intel/oneapi/setvars.sh --force

  export STD2HOME=~/software/build/std2/default
  export LD_LIBRARY_PATH=~/software/build/libcint/6.1.2:$LD_LIBRARY_PATH
  export PATH=$PATH:${STD2HOME}/bin

  std2 input.in

Example SLURM job submission with Intel oneAPI and libcint:
  #!/bin/bash
  #SBATCH --job-name=std2_calc
  #SBATCH --partition=cpu

  source /software/kemi/intel/oneapi/setvars.sh --force

  export STD2HOME=~/software/build/std2/default
  export LD_LIBRARY_PATH=~/software/build/libcint/6.1.2:$LD_LIBRARY_PATH

  ${STD2HOME}/bin/std2 input.in

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
  echo "std2 Installation Complete"
  echo "=========================================="
  echo "Executable: ${BUILD_DIR}/bin/std2"
  echo "Dependencies: ${BUILD_DIR}/DEPENDENCIES.txt"
  echo ""
  echo "Add to your shell profile:"
  echo "  export STD2HOME=${BUILD_DIR}"
  echo "  export PATH=\$PATH:\${STD2HOME}/bin"
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
