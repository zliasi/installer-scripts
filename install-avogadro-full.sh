#!/usr/bin/env bash
# Build and install Avogadro (libs + app) from source with CMake.
#
# Usage: install-avogadro-full.sh [VERSION] [SYMLINK_NAME]
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
SPGLIB_VERSION="2.3.1"
GLEW_VERSION="2.2.0"
GIT_REF=""
SPGLIB_GIT_REF=""
GLEW_GIT_REF=""
TEMP_SPGLIB_SOURCE_DIR=""
TEMP_GLEW_SOURCE_DIR=""
TEMP_LIB_SOURCE_DIR=""
TEMP_APP_SOURCE_DIR=""
IS_DEV=false
PATH_VERSION=""

if [[ "${VERSION}" =~ ^[0-9] ]]; then
  IS_DEV=false
  PATH_VERSION="${VERSION}"
else
  IS_DEV=true
  PATH_VERSION=""
fi

SPGLIB_SOURCE_DIR=""
SPGLIB_BUILD_DIR=""
SPGLIB_BUILD_SUBDIR=""
GLEW_SOURCE_DIR=""
GLEW_BUILD_DIR=""
LIB_SOURCE_DIR=""
APP_SOURCE_DIR=""
BUILD_DIR=""
LIB_BUILD_SUBDIR=""
APP_BUILD_SUBDIR=""

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
  GIT_REF="${VERSION#v}"
  SPGLIB_GIT_REF="v${SPGLIB_VERSION#v}"
  GLEW_GIT_REF="v${GLEW_VERSION}"
  TEMP_SPGLIB_SOURCE_DIR="${SRC_DIR}/spglib-${SPGLIB_VERSION}"
  TEMP_GLEW_SOURCE_DIR="${SRC_DIR}/glew-${GLEW_VERSION}"
  TEMP_LIB_SOURCE_DIR="${SRC_DIR}/avogadrolibs-${VERSION}"
  TEMP_APP_SOURCE_DIR="${SRC_DIR}/avogadroapp-${VERSION}"

  if [[ "${VERSION}" =~ ^[0-9] ]]; then
    IS_DEV=false
    PATH_VERSION="${VERSION}"
  else
    IS_DEV=true
    PATH_VERSION=""
  fi

  SPGLIB_SOURCE_DIR="${TEMP_SPGLIB_SOURCE_DIR}"
  SPGLIB_BUILD_DIR="${HOME}/software/build/spglib/${SPGLIB_VERSION}"
  SPGLIB_BUILD_SUBDIR="${SPGLIB_BUILD_DIR}/build"
  GLEW_SOURCE_DIR="${TEMP_GLEW_SOURCE_DIR}"
  GLEW_BUILD_DIR="${HOME}/software/build/glew/${GLEW_VERSION}"
  LIB_SOURCE_DIR="${TEMP_LIB_SOURCE_DIR}"
  APP_SOURCE_DIR="${TEMP_APP_SOURCE_DIR}"
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

# Download Spglib repository
#
# Exit codes:
#   0 - Success or already downloaded
#   1 - Download failed
download_spglib() {
  local temp_src="${TEMP_SPGLIB_SOURCE_DIR}"
  local archive="${SRC_DIR}/spglib-${SPGLIB_VERSION}.tar.gz"
  local download_url="https://github.com/atztogo/spglib/archive/refs/tags/${SPGLIB_GIT_REF}.tar.gz"

  if [[ ! -d "${temp_src}" ]]; then
    if [[ -f "${archive}" ]]; then
      echo "Using existing spglib archive: spglib-${SPGLIB_VERSION}.tar.gz"
      tar -xf "${archive}" -C "${SRC_DIR}" || {
        echo "Error: Spglib extraction failed" >&2
        return 1
      }
      if [[ -d "${SRC_DIR}/spglib-${SPGLIB_GIT_REF}" ]] && [[ ! -d "${temp_src}" ]]; then
        mv "${SRC_DIR}/spglib-${SPGLIB_GIT_REF}" "${temp_src}"
      fi
    else
      echo "Downloading Spglib ${SPGLIB_GIT_REF}..."
      wget -P "${SRC_DIR}" "${download_url}" -O "${archive}" || {
        echo "Error: Spglib download failed" >&2
        return 1
      }
      tar -xf "${archive}" -C "${SRC_DIR}" || {
        echo "Error: Spglib extraction failed" >&2
        return 1
      }
      if [[ -d "${SRC_DIR}/spglib-${SPGLIB_GIT_REF}" ]] && [[ ! -d "${temp_src}" ]]; then
        mv "${SRC_DIR}/spglib-${SPGLIB_GIT_REF}" "${temp_src}"
      fi
    fi
  fi

  SPGLIB_SOURCE_DIR="${temp_src}"

  mkdir -p "${SPGLIB_BUILD_DIR}" || {
    echo "Error: Failed to create SPGLIB_BUILD_DIR" >&2
    return 1
  }
}

# Configure Spglib build with CMake
#
# Exit codes:
#   0 - Success
#   1 - Configuration failed
configure_spglib_build() {
  mkdir -p "${SPGLIB_BUILD_SUBDIR}" || return 1
  cd "${SPGLIB_BUILD_SUBDIR}" || return 1

  echo "Configuring Spglib with CMake..."
  cmake "${SPGLIB_SOURCE_DIR}" \
    -DCMAKE_INSTALL_PREFIX="${SPGLIB_BUILD_DIR}" \
    -DCMAKE_BUILD_TYPE=Release || {
    echo "Error: Spglib CMake configuration failed" >&2
    return 1
  }
}

# Compile Spglib from source
#
# Exit codes:
#   0 - Success
#   1 - Compilation failed
compile_spglib() {
  cd "${SPGLIB_BUILD_SUBDIR}" || return 1

  echo "Building Spglib..."
  cmake --build . -j "$(nproc)" || {
    echo "Error: Spglib compilation failed" >&2
    return 1
  }
}

# Install Spglib using CMake install
#
# Exit codes:
#   0 - Success
#   1 - Installation failed
install_spglib() {
  cd "${SPGLIB_BUILD_SUBDIR}" || return 1

  echo "Installing Spglib to ${SPGLIB_BUILD_DIR}..."
  cmake --install . || {
    echo "Error: Spglib installation failed" >&2
    return 1
  }
}

# Clone GLEW repository
#
# Exit codes:
#   0 - Success or already cloned
#   1 - Clone failed
download_glew() {
  local temp_src="${TEMP_GLEW_SOURCE_DIR}"

  if [[ ! -d "${temp_src}" ]]; then
    echo "Cloning GLEW ${GLEW_GIT_REF}..."
    git clone --depth 1 --branch "${GLEW_GIT_REF}" \
      https://github.com/nigels-com/glew.git "${temp_src}" || {
      echo "Error: Clone failed" >&2
      return 1
    }
  fi

  GLEW_SOURCE_DIR="${temp_src}"

  mkdir -p "${GLEW_BUILD_DIR}" || {
    echo "Error: Failed to create GLEW_BUILD_DIR" >&2
    return 1
  }
}

# Build GLEW from source
#
# Exit codes:
#   0 - Success
#   1 - Build failed
build_glew() {
  cd "${GLEW_SOURCE_DIR}" || return 1

  echo "Building GLEW..."
  make GLEW_DEST="${GLEW_BUILD_DIR}" -j "$(nproc)" || {
    echo "Error: GLEW build failed" >&2
    return 1
  }
}

# Install GLEW
#
# Exit codes:
#   0 - Success
#   1 - Installation failed
install_glew() {
  cd "${GLEW_SOURCE_DIR}" || return 1

  echo "Installing GLEW to ${GLEW_BUILD_DIR}..."
  make GLEW_DEST="${GLEW_BUILD_DIR}" install || {
    echo "Error: GLEW installation failed" >&2
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

# Download Avogadro libraries repository
#
# Exit codes:
#   0 - Success or already downloaded
#   1 - Download failed
clone_lib_repository() {
  local temp_src="${TEMP_LIB_SOURCE_DIR}"
  local archive="${SRC_DIR}/avogadrolibs-${VERSION}.tar.gz"
  local download_url="https://github.com/openchemistry/avogadrolibs/archive/refs/tags/${GIT_REF}.tar.gz"

  if [[ ! -d "${temp_src}" ]]; then
    if [[ -f "${archive}" ]]; then
      echo "Using existing archive: avogadrolibs-${VERSION}.tar.gz"
      tar -xf "${archive}" -C "${SRC_DIR}" || {
        echo "Error: Extraction failed" >&2
        return 1
      }
      # GitHub archives extract with repo-TAG format
      if [[ -d "${SRC_DIR}/avogadrolibs-${GIT_REF}" ]] && [[ ! -d "${temp_src}" ]]; then
        mv "${SRC_DIR}/avogadrolibs-${GIT_REF}" "${temp_src}"
      fi
    else
      echo "Downloading Avogadro libraries ${GIT_REF}..."
      wget -P "${SRC_DIR}" "${download_url}" -O "${archive}" || {
        echo "Error: Download failed" >&2
        return 1
      }
      tar -xf "${archive}" -C "${SRC_DIR}" || {
        echo "Error: Extraction failed" >&2
        return 1
      }
      # GitHub archives extract with repo-TAG format
      if [[ -d "${SRC_DIR}/avogadrolibs-${GIT_REF}" ]] && [[ ! -d "${temp_src}" ]]; then
        mv "${SRC_DIR}/avogadrolibs-${GIT_REF}" "${temp_src}"
      fi
    fi
  fi

  if [[ "${IS_DEV}" == "true" ]]; then
    local actual_version
    actual_version=$(determine_dev_version "${temp_src}")
    PATH_VERSION="${actual_version}"
    LIB_SOURCE_DIR="${SRC_DIR}/avogadrolibs-${PATH_VERSION}"
    if [[ "${temp_src}" != "${LIB_SOURCE_DIR}" ]] && [[ -d "${temp_src}" ]]; then
      mv "${temp_src}" "${LIB_SOURCE_DIR}"
    fi
  else
    LIB_SOURCE_DIR="${SRC_DIR}/avogadrolibs-${PATH_VERSION}"
    if [[ "${temp_src}" != "${LIB_SOURCE_DIR}" ]] && [[ -d "${temp_src}" ]]; then
      mv "${temp_src}" "${LIB_SOURCE_DIR}"
    fi
  fi

  BUILD_DIR="${HOME}/software/build/avogadro/${PATH_VERSION}"
  LIB_BUILD_SUBDIR="${BUILD_DIR}/build-libs"

  mkdir -p "${BUILD_DIR}" || {
    echo "Error: Failed to create BUILD_DIR" >&2
    return 1
  }
}

# Download Avogadro application repository
#
# Exit codes:
#   0 - Success or already downloaded
#   1 - Download failed
clone_app_repository() {
  local temp_src="${TEMP_APP_SOURCE_DIR}"
  local archive="${SRC_DIR}/avogadroapp-${VERSION}.tar.gz"
  local download_url="https://github.com/openchemistry/avogadroapp/archive/refs/tags/${GIT_REF}.tar.gz"

  if [[ ! -d "${temp_src}" ]]; then
    if [[ -f "${archive}" ]]; then
      echo "Using existing archive: avogadroapp-${VERSION}.tar.gz"
      tar -xf "${archive}" -C "${SRC_DIR}" || {
        echo "Error: Extraction failed" >&2
        return 1
      }
      # GitHub archives extract with repo-TAG format
      if [[ -d "${SRC_DIR}/avogadroapp-${GIT_REF}" ]] && [[ ! -d "${temp_src}" ]]; then
        mv "${SRC_DIR}/avogadroapp-${GIT_REF}" "${temp_src}"
      fi
    else
      echo "Downloading Avogadro application ${GIT_REF}..."
      wget -P "${SRC_DIR}" "${download_url}" -O "${archive}" || {
        echo "Error: Download failed" >&2
        return 1
      }
      tar -xf "${archive}" -C "${SRC_DIR}" || {
        echo "Error: Extraction failed" >&2
        return 1
      }
      # GitHub archives extract with repo-TAG format
      if [[ -d "${SRC_DIR}/avogadroapp-${GIT_REF}" ]] && [[ ! -d "${temp_src}" ]]; then
        mv "${SRC_DIR}/avogadroapp-${GIT_REF}" "${temp_src}"
      fi
    fi
  fi

  if [[ "${IS_DEV}" == "true" ]]; then
    APP_SOURCE_DIR="${SRC_DIR}/avogadroapp-${PATH_VERSION}"
    if [[ "${temp_src}" != "${APP_SOURCE_DIR}" ]] && [[ -d "${temp_src}" ]]; then
      mv "${temp_src}" "${APP_SOURCE_DIR}"
    fi
  else
    APP_SOURCE_DIR="${SRC_DIR}/avogadroapp-${PATH_VERSION}"
    if [[ "${temp_src}" != "${APP_SOURCE_DIR}" ]] && [[ -d "${temp_src}" ]]; then
      mv "${temp_src}" "${APP_SOURCE_DIR}"
    fi
  fi

  APP_BUILD_SUBDIR="${BUILD_DIR}/build-app"

  mkdir -p "${BUILD_DIR}" || {
    echo "Error: Failed to create BUILD_DIR" >&2
    return 1
  }
}

# Configure Avogadro libraries build with CMake
#
# Exit codes:
#   0 - Success
#   1 - Configuration failed
configure_lib_build() {
  mkdir -p "${LIB_BUILD_SUBDIR}" || return 1
  cd "${LIB_BUILD_SUBDIR}" || return 1

  local cmake_prefix_path="${CMAKE_PREFIX_PATH:-}"
  if [[ -z "${cmake_prefix_path}" ]]; then
    cmake_prefix_path="${GLEW_BUILD_DIR}:${SPGLIB_BUILD_DIR}:${HOME}/software/build"
  else
    cmake_prefix_path="${GLEW_BUILD_DIR}:${SPGLIB_BUILD_DIR}:${HOME}/software/build:${cmake_prefix_path}"
  fi

  local pkg_config_path="${PKG_CONFIG_PATH:-}"
  if [[ -z "${pkg_config_path}" ]]; then
    pkg_config_path="${SPGLIB_BUILD_DIR}/lib/pkgconfig"
  else
    pkg_config_path="${SPGLIB_BUILD_DIR}/lib/pkgconfig:${pkg_config_path}"
  fi

  echo "Configuring Avogadro libraries with CMake..."
  echo "  SPGLIB_BUILD_DIR=${SPGLIB_BUILD_DIR}"
  echo "  CMAKE_PREFIX_PATH=${cmake_prefix_path}"
  echo "  LIB_SOURCE_DIR=${LIB_SOURCE_DIR}"
  [[ -d "${SPGLIB_BUILD_DIR}/lib64/cmake/Spglib" ]] && echo "  Found SpglibConfig.cmake at: ${SPGLIB_BUILD_DIR}/lib64/cmake/Spglib/" || echo "  WARNING: SpglibConfig.cmake NOT found at ${SPGLIB_BUILD_DIR}/lib64/cmake/Spglib/"
  cmake "${LIB_SOURCE_DIR}" \
    -DCMAKE_INSTALL_PREFIX="${BUILD_DIR}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="${cmake_prefix_path}" \
    -DSpglib_DIR="${SPGLIB_BUILD_DIR}/lib64/cmake/Spglib" \
    -DENABLE_TESTING=ON || {
    echo "Error: CMake configuration failed" >&2
    return 1
  }
}

# Compile Avogadro libraries from source
#
# Exit codes:
#   0 - Success
#   1 - Compilation failed
compile_lib_project() {
  cd "${LIB_BUILD_SUBDIR}" || return 1

  echo "Building Avogadro libraries..."
  cmake --build . -j "$(nproc)" || {
    echo "Error: Compilation failed" >&2
    return 1
  }
}

# Install Avogadro libraries using CMake install
#
# Exit codes:
#   0 - Success
#   1 - Installation failed
install_lib_executable() {
  cd "${LIB_BUILD_SUBDIR}" || return 1

  echo "Installing Avogadro libraries to ${BUILD_DIR}..."
  cmake --install . || {
    echo "Error: Installation failed" >&2
    return 1
  }
}

# Configure Avogadro application build with CMake
#
# Exit codes:
#   0 - Success
#   1 - Configuration failed
configure_app_build() {
  mkdir -p "${APP_BUILD_SUBDIR}" || return 1
  cd "${APP_BUILD_SUBDIR}" || return 1

  local cmake_prefix_path="${BUILD_DIR}"
  if [[ -n "${CMAKE_PREFIX_PATH:-}" ]]; then
    cmake_prefix_path="${BUILD_DIR}:${GLEW_BUILD_DIR}:${SPGLIB_BUILD_DIR}:${CMAKE_PREFIX_PATH}"
  else
    cmake_prefix_path="${BUILD_DIR}:${GLEW_BUILD_DIR}:${SPGLIB_BUILD_DIR}:${HOME}/software/build"
  fi

  local pkg_config_path="${PKG_CONFIG_PATH:-}"
  if [[ -z "${pkg_config_path}" ]]; then
    pkg_config_path="${SPGLIB_BUILD_DIR}/lib/pkgconfig"
  else
    pkg_config_path="${SPGLIB_BUILD_DIR}/lib/pkgconfig:${pkg_config_path}"
  fi

  echo "Configuring Avogadro application with CMake..."
  echo "  SPGLIB_BUILD_DIR=${SPGLIB_BUILD_DIR}"
  echo "  CMAKE_PREFIX_PATH=${cmake_prefix_path}"
  echo "  APP_SOURCE_DIR=${APP_SOURCE_DIR}"
  [[ -d "${SPGLIB_BUILD_DIR}/lib64/cmake/Spglib" ]] && echo "  Found SpglibConfig.cmake at: ${SPGLIB_BUILD_DIR}/lib64/cmake/Spglib/" || echo "  WARNING: SpglibConfig.cmake NOT found at ${SPGLIB_BUILD_DIR}/lib64/cmake/Spglib/"
  cmake "${APP_SOURCE_DIR}" \
    -DCMAKE_INSTALL_PREFIX="${BUILD_DIR}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="${cmake_prefix_path}" \
    -DSpglib_DIR="${SPGLIB_BUILD_DIR}/lib64/cmake/Spglib" \
    -DENABLE_TESTING=ON || {
    echo "Error: CMake configuration failed" >&2
    return 1
  }
}

# Compile Avogadro application from source
#
# Exit codes:
#   0 - Success
#   1 - Compilation failed
compile_app_project() {
  cd "${APP_BUILD_SUBDIR}" || return 1

  echo "Building Avogadro application..."
  cmake --build . -j "$(nproc)" || {
    echo "Error: Compilation failed" >&2
    return 1
  }
}

# Install Avogadro application using CMake install
#
# Exit codes:
#   0 - Success
#   1 - Installation failed
install_app_executable() {
  cd "${APP_BUILD_SUBDIR}" || return 1

  echo "Installing Avogadro application to ${BUILD_DIR}..."
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

# Create source archives and remove source directories
#
# Exit codes:
#   0 - Always succeeds (cleanup warnings non-fatal)
archive_source() {
  local lib_archive="${SRC_DIR}/avogadrolibs-${PATH_VERSION}.tar.gz"
  local app_archive="${SRC_DIR}/avogadroapp-${PATH_VERSION}.tar.gz"

  echo "Creating source archives..."
  tar -czf "${lib_archive}" -C "${SRC_DIR}" "avogadrolibs-${PATH_VERSION}" || {
    echo "Warning: Failed to create avogadrolibs archive" >&2
  }

  tar -czf "${app_archive}" -C "${SRC_DIR}" "avogadroapp-${PATH_VERSION}" || {
    echo "Warning: Failed to create avogadroapp archive" >&2
  }

  echo "Removing source directories..."
  rm -rf "${LIB_SOURCE_DIR}" || {
    echo "Warning: Failed to remove lib source directory" >&2
  }

  rm -rf "${APP_SOURCE_DIR}" || {
    echo "Warning: Failed to remove app source directory" >&2
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
  echo "  export CMAKE_PREFIX_PATH=\${AVOGADRO_HOME}:\$CMAKE_PREFIX_PATH"
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
  download_spglib || return 1
  configure_spglib_build || return 1
  compile_spglib || return 1
  install_spglib || return 1
  download_glew || return 1
  build_glew || return 1
  install_glew || return 1
  clone_lib_repository || return 1
  clone_app_repository || return 1
  configure_lib_build || return 1
  compile_lib_project || return 1
  install_lib_executable || return 1
  configure_app_build || return 1
  compile_app_project || return 1
  install_app_executable || return 1
  archive_source || return 1
  setup_symlink || return 1
  verify_installation || return 1
  print_setup
}

main "$@"
