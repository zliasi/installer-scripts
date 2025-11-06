#!/usr/bin/env bash
# Build and install Avogadro from source with CMake.
#
# Usage: install-avogadro.sh [VERSION] [SYMLINK_NAME]
#
# Arguments:
#   VERSION      - Release version (e.g., 1.102.1) (default: 1.102.1)
#   SYMLINK_NAME - Name for symlink (default: default)
#
# Paths:
#   Source: ~/software/src/external
#   Build:  ~/software/build/avogadro/VERSION

set -euo pipefail

readonly SRC_DIR="${HOME}/software/src/external"

VERSION="1.102.1"
SYMLINK_NAME="default"
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
  TEMP_SOURCE_DIR="${SRC_DIR}/avogadro-${VERSION}"

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
  command -v git >/dev/null || {
    echo "Error: git not found in PATH" >&2
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

# Clone Avogadro repository and determine version
#
# Exit codes:
#   0 - Success or already cloned
#   1 - Clone failed
clone_repository() {
  local temp_src="${TEMP_SOURCE_DIR}"
  local archive="${SRC_DIR}/avogadro-${VERSION}.tar.gz"

  if [[ ! -d "${temp_src}" ]]; then
    if [[ -f "${archive}" ]]; then
      echo "Using existing archive: avogadro-${VERSION}.tar.gz"
      tar -xf "${archive}" -C "${SRC_DIR}" || {
        echo "Error: Extraction failed" >&2
        return 1
      }
    else
      echo "Cloning Avogadro ${GIT_REF}..."
      git clone --depth 1 --branch "${GIT_REF}" \
        https://github.com/openchemistry/avogadroapp.git "${temp_src}" || {
        echo "Error: Clone failed" >&2
        return 1
      }
    fi
  fi

  if [[ "${IS_DEV}" == "true" ]]; then
    local actual_version
    actual_version=$(determine_dev_version "${temp_src}")
    PATH_VERSION="${actual_version}"
    SOURCE_DIR="${SRC_DIR}/avogadro-${PATH_VERSION}"
    if [[ "${temp_src}" != "${SOURCE_DIR}" ]] && [[ -d "${temp_src}" ]]; then
      mv "${temp_src}" "${SOURCE_DIR}"
    fi
    BUILD_DIR="${HOME}/software/build/avogadro/${PATH_VERSION}"
    BUILD_SUBDIR="${BUILD_DIR}/build"
  else
    SOURCE_DIR="${SRC_DIR}/avogadro-${PATH_VERSION}"
    if [[ "${temp_src}" != "${SOURCE_DIR}" ]] && [[ -d "${temp_src}" ]]; then
      mv "${temp_src}" "${SOURCE_DIR}"
    fi
    BUILD_DIR="${HOME}/software/build/avogadro/${PATH_VERSION}"
    BUILD_SUBDIR="${BUILD_DIR}/build"
  fi

  mkdir -p "${BUILD_DIR}" || {
    echo "Error: Failed to create BUILD_DIR" >&2
    return 1
  }
}

# Configure Avogadro build with CMake
#
# Exit codes:
#   0 - Success
#   1 - Configuration failed
configure_build() {
  mkdir -p "${BUILD_SUBDIR}" || return 1
  cd "${BUILD_SUBDIR}" || return 1

  echo "Configuring Avogadro with CMake..."
  cmake "${SOURCE_DIR}" \
    -DCMAKE_INSTALL_PREFIX="${BUILD_DIR}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DENABLE_TESTING=ON || {
    echo "Error: CMake configuration failed" >&2
    return 1
  }
}

# Compile Avogadro from source
#
# Exit codes:
#   0 - Success
#   1 - Compilation failed
compile_project() {
  cd "${BUILD_SUBDIR}" || return 1

  echo "Building Avogadro..."
  cmake --build . -j "$(nproc)" || {
    echo "Error: Compilation failed" >&2
    return 1
  }
}

# Install Avogadro using CMake install
#
# Exit codes:
#   0 - Success
#   1 - Installation failed
install_executable() {
  cd "${BUILD_SUBDIR}" || return 1

  echo "Installing Avogadro to ${BUILD_DIR}..."
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

# Verify Avogadro executable was installed successfully
#
# Exit codes:
#   0 - Success
#   1 - Verification failed
verify_installation() {
  [[ -x "${BUILD_DIR}/bin/avogadro" ]] || {
    echo "Error: Avogadro executable not found" >&2
    return 1
  }
  echo "Installed to: ${BUILD_DIR}"
}

# Create source archive and remove source directory
#
# Exit codes:
#   0 - Always succeeds (cleanup warnings non-fatal)
archive_source() {
  local archive="${SRC_DIR}/avogadro-${PATH_VERSION}.tar.gz"

  echo "Creating source archive..."
  tar -czf "${archive}" -C "${SRC_DIR}" "avogadro-${PATH_VERSION}" || {
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
  echo "Avogadro Installation Complete"
  echo "=========================================="
  echo "Executable: ${BUILD_DIR}/bin/avogadro"
  echo ""
  echo "Add to your shell profile:"
  echo "  export AVOGADRO_HOME=${BUILD_DIR}"
  echo "  export PATH=\$PATH:\${AVOGADRO_HOME}/bin"
  echo ""
  echo "Usage:"
  echo "  avogadro                   # Launch GUI"
  echo "  avogadro file.xyz          # Open molecule file"
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
