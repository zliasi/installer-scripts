#!/usr/bin/env bash
# Build and install MOLDEN (graphical molecular visualization) from source.
#
# Usage: install-molden.sh [VERSION] [SYMLINK_NAME]
#
# Arguments:
#   VERSION      - MOLDEN version (e.g., 7.3) (default: 7.3)
#   SYMLINK_NAME - Name for symlink (default: default)
#
# Notes:
#   Compiles gmolden (graphical version) from source
#   Requires X11 and OpenGL development libraries for graphical features
#
# Paths:
#   Source: ~/software/src/external
#   Build:  ~/software/build/molden/VERSION

set -euo pipefail

readonly SRC_DIR="${HOME}/software/src/external"

VERSION="${1:-7.3}"
SYMLINK_NAME="${2:-default}"
TEMP_SOURCE_DIR="${SRC_DIR}/molden${VERSION}"
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
  command -v wget >/dev/null || {
    echo "Error: wget not found in PATH" >&2
    return 1
  }
  command -v gfortran >/dev/null || {
    echo "Error: gfortran not found in PATH" >&2
    return 1
  }
  command -v make >/dev/null || {
    echo "Error: make not found in PATH" >&2
    return 1
  }
}

# Check for optional graphics libraries (X11, OpenGL)
#
# Exit codes:
#   0 - Always succeeds (graphics libraries are optional)
check_graphics_libraries() {
  pkg-config x11 >/dev/null 2>&1 || {
    echo "Warning: X11 development libraries not found (X11-based visualization may be disabled)" >&2
  }
  pkg-config gl >/dev/null 2>&1 || {
    echo "Warning: OpenGL development libraries not found (gmolden graphical features may be limited)" >&2
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

# Download MOLDEN source and determine version
#
# Exit codes:
#   0 - Success or already downloaded
#   1 - Download failed
download_source() {
  local temp_src="${TEMP_SOURCE_DIR}"
  local archive="${SRC_DIR}/molden${VERSION}.tar.gz"
  local download_url="https://ftp.science.ru.nl/Molden/molden${VERSION}.tar.gz"

  if [[ ! -d "${temp_src}" ]]; then
    if [[ -f "${archive}" ]]; then
      echo "Using existing archive: molden${VERSION}.tar.gz"
      tar -xf "${archive}" -C "${SRC_DIR}" || {
        echo "Error: Extraction failed" >&2
        return 1
      }
    else
      echo "Downloading MOLDEN ${VERSION}..."
      wget -P "${SRC_DIR}" "${download_url}" || {
        echo "Error: Download failed" >&2
        echo "URL: ${download_url}" >&2
        return 1
      }
      tar -xf "${archive}" -C "${SRC_DIR}" || {
        echo "Error: Extraction failed" >&2
        return 1
      }
    fi
  fi

  if [[ "${IS_DEV}" == "true" ]]; then
    PATH_VERSION="$(date +%Y.%m)-dev"
    SOURCE_DIR="${SRC_DIR}/molden${PATH_VERSION}"
    if [[ "${temp_src}" != "${SOURCE_DIR}" ]] && [[ -d "${temp_src}" ]]; then
      mv "${temp_src}" "${SOURCE_DIR}"
    fi
  else
    SOURCE_DIR="${SRC_DIR}/molden${PATH_VERSION}"
    if [[ "${temp_src}" != "${SOURCE_DIR}" ]] && [[ -d "${temp_src}" ]]; then
      mv "${temp_src}" "${SOURCE_DIR}"
    fi
  fi

  BUILD_DIR="${HOME}/software/build/molden/${PATH_VERSION}"
  BUILD_SUBDIR="${BUILD_DIR}/build"

  mkdir -p "${BUILD_DIR}" || {
    echo "Error: Failed to create BUILD_DIR" >&2
    return 1
  }
}

# Build MOLDEN from source with gfortran
#
# Exit codes:
#   0 - Success
#   1 - Build failed
build_source() {
  cd "${SOURCE_DIR}" || return 1

  echo "Building MOLDEN ${VERSION} with gfortran..."
  make FC=gfortran -j "$(nproc)" || {
    echo "Error: Build failed" >&2
    return 1
  }
}

# Install MOLDEN executables
#
# Exit codes:
#   0 - Success
#   1 - Installation failed
install_executables() {
  cd "${SOURCE_DIR}" || return 1

  echo "Installing MOLDEN to ${BUILD_DIR}..."
  mkdir -p "${BUILD_DIR}/bin"

  if [[ -f "gmolden" ]]; then
    cp gmolden "${BUILD_DIR}/bin/" || {
      echo "Error: Failed to copy gmolden" >&2
      return 1
    }
    chmod +x "${BUILD_DIR}/bin/gmolden"
  fi

  if [[ -f "molden" ]]; then
    cp molden "${BUILD_DIR}/bin/" || {
      echo "Error: Failed to copy molden" >&2
      return 1
    }
    chmod +x "${BUILD_DIR}/bin/molden"
  fi

  if [[ -f "ambfor" ]]; then
    cp ambfor "${BUILD_DIR}/bin/" || {
      echo "Error: Failed to copy ambfor" >&2
      return 1
    }
    chmod +x "${BUILD_DIR}/bin/ambfor"
  fi

  if [[ -f "ambmd" ]]; then
    cp ambmd "${BUILD_DIR}/bin/" || {
      echo "Error: Failed to copy ambmd" >&2
      return 1
    }
    chmod +x "${BUILD_DIR}/bin/ambmd"
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

# Verify MOLDEN executables were installed successfully
#
# Exit codes:
#   0 - Success
#   1 - Verification failed
verify_installation() {
  [[ -x "${BUILD_DIR}/bin/gmolden" ]] || [[ -x "${BUILD_DIR}/bin/molden" ]] || {
    echo "Error: MOLDEN executables not found" >&2
    return 1
  }
  echo "Installed to: ${BUILD_DIR}"
}

# Create source archive and remove source directory
#
# Exit codes:
#   0 - Always succeeds (cleanup warnings non-fatal)
archive_source() {
  local archive="${SRC_DIR}/molden${PATH_VERSION}.tar.gz"

  echo "Creating source archive..."
  tar -czf "${archive}" -C "${SRC_DIR}" "molden-${PATH_VERSION}" || {
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
  echo "MOLDEN Installation Complete"
  echo "=========================================="
  echo "Executable: ${BUILD_DIR}/bin/gmolden (graphical)"
  echo "            ${BUILD_DIR}/bin/molden (command-line)"
  echo ""
  echo "Add to your shell profile:"
  echo "  export MOLDEN_HOME=${BUILD_DIR}"
  echo "  export PATH=\$PATH:\${MOLDEN_HOME}/bin"
  echo ""
  echo "Usage:"
  echo "  gmolden file.log       # Launch graphical interface"
  echo "  molden file.log        # Command-line visualization"
  echo "=========================================="
  echo ""
}

main() {
  validate_parameters || return 1
  check_dependencies || return 1
  check_graphics_libraries
  create_directories || return 1
  download_source || return 1
  build_source || return 1
  install_executables || return 1
  archive_source || return 1
  setup_symlink || return 1
  verify_installation || return 1
  print_setup
}

main "$@"
