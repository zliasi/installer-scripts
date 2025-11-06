#!/usr/bin/env bash
# Build and install GLEW (OpenGL Extension Wrangler) from source.
#
# Usage: install-glew.sh [VERSION] [SYMLINK_NAME]
#
# Arguments:
#   VERSION      - GLEW version (e.g., 2.2.0) (default: 2.2.0)
#   SYMLINK_NAME - Name for symlink (default: default)
#
# Paths:
#   Source: ~/software/src/external
#   Build:  ~/software/build/glew/VERSION

set -euo pipefail

readonly SRC_DIR="${HOME}/software/src/external"

VERSION="${1:-2.2.0}"
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
  GIT_REF="${VERSION}"
  TEMP_SOURCE_DIR="${SRC_DIR}/glew-${VERSION}"

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

# Download GLEW source
#
# Exit codes:
#   0 - Success or already downloaded
#   1 - Download failed
download_source() {
  local temp_src="${TEMP_SOURCE_DIR}"
  local archive="${SRC_DIR}/glew-${VERSION}.tar.gz"
  local download_url="https://github.com/nigels-com/glew/archive/refs/tags/${VERSION}.tar.gz"

  if [[ ! -d "${temp_src}" ]]; then
    if [[ -f "${archive}" ]]; then
      echo "Using existing archive: glew-${VERSION}.tar.gz"
      tar -xf "${archive}" -C "${SRC_DIR}" || {
        echo "Error: Extraction failed" >&2
        return 1
      }
      if [[ -d "${SRC_DIR}/glew-${VERSION}" ]] && [[ ! -d "${temp_src}" ]]; then
        mv "${SRC_DIR}/glew-${VERSION}" "${temp_src}"
      fi
    else
      echo "Downloading GLEW ${VERSION}..."
      wget -P "${SRC_DIR}" "${download_url}" -O "${archive}" || {
        echo "Error: Download failed" >&2
        return 1
      }
      tar -xf "${archive}" -C "${SRC_DIR}" || {
        echo "Error: Extraction failed" >&2
        return 1
      }
      if [[ -d "${SRC_DIR}/glew-${VERSION}" ]] && [[ ! -d "${temp_src}" ]]; then
        mv "${SRC_DIR}/glew-${VERSION}" "${temp_src}"
      fi
    fi
  fi

  SOURCE_DIR="${temp_src}"
  BUILD_DIR="${HOME}/software/build/glew/${PATH_VERSION}"

  mkdir -p "${BUILD_DIR}" || {
    echo "Error: Failed to create BUILD_DIR" >&2
    return 1
  }
}

# Build GLEW from source
#
# Exit codes:
#   0 - Success
#   1 - Build failed
build_project() {
  cd "${SOURCE_DIR}" || return 1

  echo "Building GLEW..."
  make GLEW_DEST="${BUILD_DIR}" -j "$(nproc)" || {
    echo "Error: Build failed" >&2
    return 1
  }
}

# Install GLEW
#
# Exit codes:
#   0 - Success
#   1 - Installation failed
install_executable() {
  cd "${SOURCE_DIR}" || return 1

  echo "Installing GLEW to ${BUILD_DIR}..."
  make GLEW_DEST="${BUILD_DIR}" install || {
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

# Verify GLEW library was installed successfully
#
# Exit codes:
#   0 - Success
#   1 - Verification failed
verify_installation() {
  [[ -f "${BUILD_DIR}/lib/libGLEW.so" ]] || [[ -f "${BUILD_DIR}/lib64/libGLEW.so" ]] || {
    echo "Error: GLEW library not found" >&2
    return 1
  }
  echo "Installed to: ${BUILD_DIR}"
}

# Create source archive and remove source directory
#
# Exit codes:
#   0 - Always succeeds (cleanup warnings non-fatal)
archive_source() {
  local archive="${SRC_DIR}/glew-${PATH_VERSION}.tar.gz"

  echo "Creating source archive..."
  tar -czf "${archive}" -C "${SRC_DIR}" "glew-${PATH_VERSION}" || {
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
  echo "GLEW Installation Complete"
  echo "=========================================="
  echo "Library: ${BUILD_DIR}/lib/libGLEW.so"
  echo ""
  echo "Add to your shell profile or CMake builds:"
  echo "  export GLEW_HOME=${BUILD_DIR}"
  echo "  export CMAKE_PREFIX_PATH=\$CMAKE_PREFIX_PATH:\${GLEW_HOME}"
  echo "=========================================="
  echo ""
}

main() {
  parse_arguments "$@" || return 1
  validate_parameters || return 1
  check_dependencies || return 1
  create_directories || return 1
  download_source || return 1
  build_project || return 1
  install_executable || return 1
  archive_source || return 1
  setup_symlink || return 1
  verify_installation || return 1
  print_setup
}

main "$@"
