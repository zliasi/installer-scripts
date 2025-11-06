#!/usr/bin/env bash
# Install Orca from precompiled binaries.
#
# Usage: install-orca.sh <tar-file> [SYMLINK_NAME]
#
# Arguments:
#   tar-file     - Path to Orca tar archive (required)
#   SYMLINK_NAME - Name for symlink (default: default)
#
# Paths:
#   Build:  ~/software/build/orca/VERSION (VERSION parsed from filename)

set -euo pipefail

# Parse version from Orca tar filename
# Expected format: orca_X_Y_Z_*.tar.{xz,gz}
# Returns: X.Y.Z
parse_version_from_filename() {
  local filename="$1"
  local basename
  basename="$(basename "${filename}")"

  # Extract version pattern (e.g., orca_6_1_0_... -> 6_1_0)
  if [[ "${basename}" =~ ^orca_([0-9]+)_([0-9]+)_([0-9]+)_ ]]; then
    echo "${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
  else
    echo "Error: Cannot parse version from filename: ${filename}" >&2
    echo "Expected format: orca_X_Y_Z_*.tar.{xz,gz}" >&2
    return 1
  fi
}

readonly TAR_FILE="${1}"
readonly SYMLINK_NAME="${2:-default}"
readonly VERSION="$(parse_version_from_filename "${TAR_FILE}")"
readonly BUILD_DIR="${HOME}/software/build/orca/${VERSION}"
readonly SYMLINK_DIR="$(dirname "${BUILD_DIR}")"

# Validate tar file argument and file type
#
# Exit codes:
#   0 - Valid tar file
#   1 - Invalid or missing tar file
validate_tar_file() {
  [[ -n "${TAR_FILE}" ]] || {
    echo "Error: tar-file argument is required" >&2
    echo "Usage: install-orca.sh <tar-file> [SYMLINK_NAME]" >&2
    return 1
  }

  [[ -f "${TAR_FILE}" ]] || {
    echo "Error: Tar file not found: ${TAR_FILE}" >&2
    return 1
  }

  [[ "${TAR_FILE}" =~ \.(tar\.xz|tar\.gz)$ ]] || {
    echo "Error: File must be .tar.xz or .tar.gz: ${TAR_FILE}" >&2
    return 1
  }
}

# Create build directory
#
# Exit codes:
#   0 - Success
#   1 - Failed to create directory
create_directories() {
  mkdir -p "${BUILD_DIR}" || {
    echo "Error: Failed to create directory" >&2
    return 1
  }
}

# Extract Orca archive directly to build directory
#
# Exit codes:
#   0 - Success
#   1 - Extraction failed
extract_archive() {
  echo "Extracting Orca ${VERSION} to ${BUILD_DIR}..."
  tar -xf "${TAR_FILE}" -C "${BUILD_DIR}" --strip-components=1 || {
    echo "Error: Extraction failed" >&2
    return 1
  }
}

# Create default symlink to installed version
#
# Exit codes:
#   0 - Success
#   1 - Failed to create symlink
setup_symlink() {
  local symlink_path="${SYMLINK_DIR}/${SYMLINK_NAME}"

  rm -f "${symlink_path}"
  ln -sfn "${VERSION}" "${symlink_path}" || {
    echo "Error: Failed to create symlink" >&2
    return 1
  }
}

# Verify Orca executable was installed successfully
#
# Exit codes:
#   0 - Success
#   1 - Verification failed
verify_installation() {
  [[ -x "${BUILD_DIR}/orca" ]] || {
    echo "Error: orca executable not found" >&2
    return 1
  }
  echo "Installed to: ${BUILD_DIR}"
}

main() {
  validate_tar_file || return 1
  create_directories || return 1
  extract_archive || return 1
  setup_symlink || return 1
  verify_installation
}

main "$@"
