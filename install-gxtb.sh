#!/usr/bin/env bash
# Install g-xTB from repository binaries and parameters.
#
# Usage: install-gxtb.sh [VERSION] [SYMLINK_NAME]
#
# Arguments:
#   VERSION      - Release version (e.g., 1.1.0) (default: 1.1.0)
#   SYMLINK_NAME - Name for symlink (default: default)
#
# Paths:
#   Source: ~/software/src/external
#   Build:  ~/software/build/gxtb/VERSION

set -euo pipefail

readonly VERSION="${1:-1.1.0}"
readonly SYMLINK_NAME="${2:-default}"
readonly GIT_REF="v${VERSION#v}"
readonly SRC_DIR="${HOME}/software/src/external"
readonly TEMP_SOURCE_DIR="${SRC_DIR}/g-xtb-${VERSION}"

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

# Clone g-xTB repository and determine version
#
# Exit codes:
#   0 - Success or already cloned
#   1 - Clone failed
clone_repository() {
  local temp_src="${TEMP_SOURCE_DIR}"
  local archive="${SRC_DIR}/g-xtb-${VERSION}.tar.gz"

  if [[ ! -d "${temp_src}" ]]; then
    if [[ -f "${archive}" ]]; then
      echo "Using existing archive: g-xtb-${VERSION}.tar.gz"
      tar -xf "${archive}" -C "${SRC_DIR}" || {
        echo "Error: Extraction failed" >&2
        return 1
      }
    else
      echo "Cloning g-xTB ${GIT_REF}..."
      git clone --branch "${GIT_REF}" \
        https://github.com/grimme-lab/g-xtb.git "${temp_src}" || {
        echo "Error: Clone failed" >&2
        return 1
      }
    fi
  fi

  if [[ "${IS_DEV}" == "true" ]]; then
    local actual_version
    actual_version=$(determine_dev_version "${temp_src}")
    PATH_VERSION="${actual_version}"
    SOURCE_DIR="${SRC_DIR}/g-xtb-${PATH_VERSION}"
    if [[ "${temp_src}" != "${SOURCE_DIR}" ]] && [[ -d "${temp_src}" ]]; then
      mv "${temp_src}" "${SOURCE_DIR}"
    fi
    BUILD_DIR="${HOME}/software/build/gxtb/${PATH_VERSION}"
  else
    SOURCE_DIR="${SRC_DIR}/g-xtb-${PATH_VERSION}"
    if [[ "${temp_src}" != "${SOURCE_DIR}" ]] && [[ -d "${temp_src}" ]]; then
      mv "${temp_src}" "${SOURCE_DIR}"
    fi
    BUILD_DIR="${HOME}/software/build/gxtb/${PATH_VERSION}"
  fi

  mkdir -p "${BUILD_DIR}" || {
    echo "Error: Failed to create BUILD_DIR" >&2
    return 1
  }
}

# Copy g-xTB binaries and parameter files to build directory
#
# Exit codes:
#   0 - Success
#   1 - Copy failed
copy_binaries_and_parameters() {
  echo "Copying g-xTB binaries and parameters..."

  cp "${SOURCE_DIR}/binary/gxtb" "${BUILD_DIR}/" || {
    echo "Error: Failed to copy gxtb binary" >&2
    return 1
  }

  mkdir -p "${BUILD_DIR}/parameters"
  cp -a "${SOURCE_DIR}/parameters"/. "${BUILD_DIR}/parameters/" || {
    echo "Error: Failed to copy parameters" >&2
    return 1
  }

  chmod +x "${BUILD_DIR}/gxtb"
}

# Create default symlink to installed version
#
# Exit codes:
#   0 - Success
#   1 - Failed to create symlink
setup_symlink() {
  local default_link="${HOME}/software/build/gxtb/${SYMLINK_NAME}"

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
  local archive="${SRC_DIR}/g-xtb-${PATH_VERSION}.tar.gz"

  echo "Creating source archive..."
  tar -czf "${archive}" -C "${SRC_DIR}" "g-xtb-${PATH_VERSION}" || {
    echo "Warning: Failed to create archive" >&2
  }

  echo "Removing source directory..."
  rm -rf "${SOURCE_DIR}" || {
    echo "Warning: Failed to remove source directory" >&2
  }
}

# Verify g-xTB executable and parameters were installed successfully
#
# Exit codes:
#   0 - Success
#   1 - Verification failed
verify_installation() {
  [[ -x "${BUILD_DIR}/gxtb" ]] || {
    echo "Error: gxtb executable not found" >&2
    return 1
  }
  [[ -d "${BUILD_DIR}/parameters" ]] || {
    echo "Error: parameters directory not found" >&2
    return 1
  }
  echo "Installed to: ${BUILD_DIR}"
  echo "Set GXTBHOME=${BUILD_DIR}/parameters to use g-xTB"
}

main() {
  validate_parameters || return 1
  create_directories || return 1
  clone_repository || return 1
  copy_binaries_and_parameters || return 1
  archive_source || return 1
  setup_symlink || return 1
  verify_installation
}

main "$@"
