#!/usr/bin/env bash
# Build and install Spglib (crystal symmetry operations) from source.
#
# Usage: install-spglib.sh [VERSION] [SYMLINK_NAME]
#
# Arguments:
#   VERSION      - Spglib version (e.g., 2.3.1) (default: 2.3.1)
#   SYMLINK_NAME - Name for symlink (default: default)
#
# Paths:
#   Source: ~/software/src/external
#   Build:  ~/software/build/spglib/VERSION

set -euo pipefail

readonly SRC_DIR="${HOME}/software/src/external"

VERSION="${1:-2.3.1}"
SYMLINK_NAME="${2:-default}"
GIT_REF=""
TEMP_SOURCE_DIR=""
IS_DEV=false
PATH_VERSION=""

if [[ "${VERSION}" =~ ^[0-9] ]]; then
  IS_DEV=false
  PATH_VERSION="${VERSION}"
else
  IS_DEV=true
  PATH_VERSION=""
fi

SOURCE_DIR=""
BUILD_DIR=""
BUILD_SUBDIR=""

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
  local arg_count=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
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
  GIT_REF="v${VERSION#v}"
  TEMP_SOURCE_DIR="${SRC_DIR}/spglib-${VERSION}"

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
  command -v make >/dev/null || {
    echo "Error: make not found in PATH" >&2
    return 1
  }
  command -v wget >/dev/null || {
    echo "Error: wget not found in PATH" >&2
    return 1
  }
  command -v gcc >/dev/null || {
    echo "Error: gcc not found in PATH" >&2
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

# Download Spglib repository
#
# Exit codes:
#   0 - Success or already downloaded
#   1 - Download failed
download_source() {
  local temp_src="${TEMP_SOURCE_DIR}"
  local archive="${SRC_DIR}/spglib-${VERSION}.tar.gz"
  local download_url="https://github.com/atztogo/spglib/archive/refs/tags/${GIT_REF}.tar.gz"

  if [[ ! -d "${temp_src}" ]]; then
    if [[ -f "${archive}" ]]; then
      echo "Using existing archive: spglib-${VERSION}.tar.gz"
      tar -xf "${archive}" -C "${SRC_DIR}" || {
        echo "Error: Extraction failed" >&2
        return 1
      }
      # GitHub archives extract with repo-TAG format
      if [[ -d "${SRC_DIR}/spglib-${GIT_REF}" ]] && [[ ! -d "${temp_src}" ]]; then
        mv "${SRC_DIR}/spglib-${GIT_REF}" "${temp_src}"
      fi
    else
      echo "Downloading Spglib ${GIT_REF}..."
      wget -P "${SRC_DIR}" "${download_url}" -O "${archive}" || {
        echo "Error: Download failed" >&2
        return 1
      }
      tar -xf "${archive}" -C "${SRC_DIR}" || {
        echo "Error: Extraction failed" >&2
        return 1
      }
      # GitHub archives extract with repo-TAG format
      if [[ -d "${SRC_DIR}/spglib-${GIT_REF}" ]] && [[ ! -d "${temp_src}" ]]; then
        mv "${SRC_DIR}/spglib-${GIT_REF}" "${temp_src}"
      fi
    fi
  fi

  if [[ "${IS_DEV}" == "true" ]]; then
    local actual_version
    actual_version=$(determine_dev_version "${temp_src}")
    PATH_VERSION="${actual_version}"
    SOURCE_DIR="${SRC_DIR}/spglib-${PATH_VERSION}"
    if [[ "${temp_src}" != "${SOURCE_DIR}" ]] && [[ -d "${temp_src}" ]]; then
      mv "${temp_src}" "${SOURCE_DIR}"
    fi
  else
    SOURCE_DIR="${SRC_DIR}/spglib-${PATH_VERSION}"
    if [[ "${temp_src}" != "${SOURCE_DIR}" ]] && [[ -d "${temp_src}" ]]; then
      mv "${temp_src}" "${SOURCE_DIR}"
    fi
  fi

  BUILD_DIR="${HOME}/software/build/spglib/${PATH_VERSION}"
  BUILD_SUBDIR="${BUILD_DIR}/build"

  mkdir -p "${BUILD_DIR}" || {
    echo "Error: Failed to create BUILD_DIR" >&2
    return 1
  }
}

# Configure Spglib build with CMake
#
# Exit codes:
#   0 - Success
#   1 - Configuration failed
configure_build() {
  mkdir -p "${BUILD_SUBDIR}" || return 1
  cd "${BUILD_SUBDIR}" || return 1

  echo "Configuring Spglib with CMake..."
  cmake "${SOURCE_DIR}" \
    -DCMAKE_INSTALL_PREFIX="${BUILD_DIR}" \
    -DCMAKE_BUILD_TYPE=Release || {
    echo "Error: CMake configuration failed" >&2
    return 1
  }
}

# Compile Spglib from source
#
# Exit codes:
#   0 - Success
#   1 - Compilation failed
compile_project() {
  cd "${BUILD_SUBDIR}" || return 1

  echo "Building Spglib..."
  cmake --build . -j "$(nproc)" || {
    echo "Error: Compilation failed" >&2
    return 1
  }
}

# Install Spglib using CMake install
#
# Exit codes:
#   0 - Success
#   1 - Installation failed
install_executable() {
  cd "${BUILD_SUBDIR}" || return 1

  echo "Installing Spglib to ${BUILD_DIR}..."
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
  local symlink_dir
  symlink_dir="$(dirname "${BUILD_DIR}")"
  local symlink_path="${symlink_dir}/${SYMLINK_NAME}"

  rm -f "${symlink_path}"
  ln -sfn "${PATH_VERSION}" "${symlink_path}" || {
    echo "Error: Failed to create symlink" >&2
    return 1
  }
}

# Verify Spglib library was installed successfully
#
# Exit codes:
#   0 - Success
#   1 - Verification failed
verify_installation() {
  [[ -f "${BUILD_DIR}/lib/libsymspacegroup.so" ]] || [[ -f "${BUILD_DIR}/lib/libsymspacegroup.a" ]] || {
    echo "Error: Spglib library not found" >&2
    return 1
  }
  echo "Installed to: ${BUILD_DIR}"
}

# Create source archive and remove source directory
#
# Exit codes:
#   0 - Always succeeds (cleanup warnings non-fatal)
archive_source() {
  local archive="${SRC_DIR}/spglib-${PATH_VERSION}.tar.gz"

  echo "Creating source archive..."
  tar -czf "${archive}" -C "${SRC_DIR}" "spglib-${PATH_VERSION}" || {
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
  echo ""
  echo "=========================================="
  echo "Spglib Installation Complete"
  echo "=========================================="
  echo "Library: ${BUILD_DIR}/lib/libsymspacegroup.so"
  echo ""
  echo "Add to your shell profile or CMake builds:"
  echo "  export SPGLIB_HOME=${BUILD_DIR}"
  echo "  export CMAKE_PREFIX_PATH=\$CMAKE_PREFIX_PATH:\${SPGLIB_HOME}"
  echo "  export PKG_CONFIG_PATH=\$PKG_CONFIG_PATH:\${SPGLIB_HOME}/lib/pkgconfig"
  echo "=========================================="
  echo ""
}

main() {
  parse_arguments "$@" || return 1
  validate_parameters || return 1
  check_dependencies || return 1
  create_directories || return 1
  download_source || return 1
  configure_build || return 1
  compile_project || return 1
  install_executable || return 1
  archive_source || return 1
  setup_symlink || return 1
  verify_installation || return 1
  print_setup
}

main "$@"
