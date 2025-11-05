#!/usr/bin/env bash
# Generate siteconfig.py for GPAW compilation.
#
# Usage: generate-gpaw-siteconfig.sh [OPTIONS]
#
# Options:
#   --gpaw-version VERSION      - GPAW version or 'default' (default: 25.1.0)
#   --openmpi-version VERSION   - OpenMPI version or 'default' (default: 5.0.8)
#   --openblas-version VERSION  - OpenBLAS version or 'default' (default: 0.3.28)
#   --libxc-version VERSION     - libxc version or 'default' (optional, default: 7.0.0)
#   --precision PRECISION       - Integer size: lp64 or ilp64 (default: lp64)
#   --output FILE               - Output file path (default: prints to stdout)
#
# Examples:
#   # Use specific versions
#   ./generate-gpaw-siteconfig.sh --openmpi-version 5.0.8 --openblas-version 0.3.28
#
#   # Use default symlinks
#   ./generate-gpaw-siteconfig.sh --openmpi-version default --openblas-version default
#
#   # Use defaults from installations
#   ./generate-gpaw-siteconfig.sh

set -euo pipefail

readonly GPAW_HOME="${HOME}/software/build/gpaw"
readonly OPENMPI_HOME="${HOME}/software/build/openmpi"
readonly OPENBLAS_HOME="${HOME}/software/build/openblas"
readonly LIBXC_HOME="${HOME}/software/build/libxc"

GPAW_VERSION="25.1.0"
OPENMPI_VERSION="5.0.8"
OPENBLAS_VERSION="0.3.28"
LIBXC_VERSION="7.0.0"
PRECISION="lp64"
OUTPUT_FILE=""

# Parse command line arguments
#
# Exit codes:
#   0 - Arguments parsed successfully
#   1 - Unknown argument provided
parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --gpaw-version)
        GPAW_VERSION="$2"
        shift 2
        ;;
      --openmpi-version)
        OPENMPI_VERSION="$2"
        shift 2
        ;;
      --openblas-version)
        OPENBLAS_VERSION="$2"
        shift 2
        ;;
      --libxc-version)
        LIBXC_VERSION="$2"
        shift 2
        ;;
      --precision)
        PRECISION="$2"
        shift 2
        ;;
      --output)
        OUTPUT_FILE="$2"
        shift 2
        ;;
      *)
        echo "Unknown option: $1" >&2
        return 1
        ;;
    esac
  done
}

# Resolve actual directory path from version or default symlink
#
# Usage: resolve_dependency_path <home> <software> <version> <precision>
#
# Exit codes:
#   0 - Path resolved successfully
#   1 - Path not found
resolve_dependency_path() {
  local home="$1"
  local software="$2"
  local version="$3"
  local precision="$4"

  if [[ "${version}" == "default" ]]; then
    local link_path="${home}/software/build/${software}/default"
    if [[ -L "${link_path}" ]]; then
      local target
      target=$(readlink "${link_path}")
      echo "${home}/software/build/${software}/${target}"
      return 0
    else
      echo "Error: default symlink not found at ${link_path}" >&2
      return 1
    fi
  else
    if [[ -n "${precision}" && "${precision}" != "none" ]]; then
      local versioned_path="${home}/software/build/${software}/${version}-${precision}"
      if [[ -d "${versioned_path}" ]]; then
        echo "${versioned_path}"
        return 0
      fi
    else
      local simple_path="${home}/software/build/${software}/${version}"
      if [[ -d "${simple_path}" ]]; then
        echo "${simple_path}"
        return 0
      fi
    fi
    return 1
  fi
}

# Validate that all required parameters are correct
#
# Exit codes:
#   0 - Parameters valid
#   1 - Parameters invalid
validate_parameters() {
  [[ "${PRECISION}" =~ ^(lp64|ilp64)$ ]] || {
    echo "Error: PRECISION must be lp64 or ilp64" >&2
    return 1
  }
}

# Validate that all required dependencies exist
#
# Exit codes:
#   0 - All dependencies found
#   1 - One or more dependencies missing
validate_dependencies() {
  resolve_dependency_path "${HOME}" "openmpi" "${OPENMPI_VERSION}" "${PRECISION}" || {
    echo "Error: OpenMPI not found (version: ${OPENMPI_VERSION}, precision: ${PRECISION})" >&2
    return 1
  }
  resolve_dependency_path "${HOME}" "openblas" "${OPENBLAS_VERSION}" "${PRECISION}" || {
    echo "Error: OpenBLAS not found (version: ${OPENBLAS_VERSION}, precision: ${PRECISION})" >&2
    return 1
  }
  resolve_dependency_path "${HOME}" "libxc" "${LIBXC_VERSION}" "none" || {
    echo "Error: libxc not found (version: ${LIBXC_VERSION})" >&2
    return 1
  }
}

# Generate GPAW siteconfig.py configuration
#
# Exit codes:
#   0 - Success
#   1 - Failed to resolve dependencies
generate_siteconfig() {
  local openmpi_dir
  local openblas_dir
  local libxc_dir

  openmpi_dir=$(resolve_dependency_path "${HOME}" "openmpi" "${OPENMPI_VERSION}" "${PRECISION}") || return 1
  openblas_dir=$(resolve_dependency_path "${HOME}" "openblas" "${OPENBLAS_VERSION}" "${PRECISION}") || return 1
  libxc_dir=$(resolve_dependency_path "${HOME}" "libxc" "${LIBXC_VERSION}" "none") || return 1

  cat << 'EOF'
# GPAW build configuration
# Auto-generated siteconfig.py

# Compiler settings
compiler_flags = {}

# MPI settings
mpi = True

# Libraries
libraries = []
library_dirs = []
include_dirs = []

EOF

  cat << EOFCONFIG
# OpenMPI
mpi_prefix = '${openmpi_dir}'
mpi_include_dir = '${openmpi_dir}/include'

# OpenBLAS
blas_include_dirs = ['${openblas_dir}/include']
blas_libraries = ['openblas']
blas_library_dirs = ['${openblas_dir}/lib']

# libxc
libxc = True
libxc_prefix = '${libxc_dir}'

# Build settings
extra_compile_args = ['-O3', '-march=native', '-fPIC']
EOFCONFIG
}

# Write generated siteconfig to file or stdout
#
# Exit codes:
#   0 - Success
#   1 - Failed to write output
write_output() {
  if [[ -z "${OUTPUT_FILE}" ]]; then
    generate_siteconfig
  else
    generate_siteconfig > "${OUTPUT_FILE}" || {
      echo "Error: Failed to write to ${OUTPUT_FILE}" >&2
      return 1
    }
    echo "Generated: ${OUTPUT_FILE}" >&2
  fi
}

# Main entry point
#
# Exit codes:
#   0 - Success
#   1 - Failure
main() {
  parse_arguments "$@" || return 1
  validate_parameters || return 1
  validate_dependencies || return 1
  write_output
}

main "$@"
