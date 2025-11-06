# installer-scripts

Personal installer scripts for HPC software.

## Scripts

- **generate-gpaw-siteconfig.sh** - Generate siteconfig.py for GPAW compilation
- **install-cfour.sh** - Install CFOUR (quantum chemistry) with MPI support
- **install-dalton.sh** - Install Dalton (quantum chemistry) with precision options
- **install-dirac.sh** - Build and install DIRAC (quantum chemistry) with CMake
- **install-glew.sh** - Build and install GLEW (OpenGL Extension Wrangler)
- **install-gpaw.sh** - Install GPAW (density functional theory) with Python venv
- **install-gxtb.sh** - Install g-xTB (extended tight-binding) from binaries
- **install-libxc.sh** - Install libxc (exchange-correlation library)
- **install-molden.sh** - Build and install MOLDEN (molecular visualization)
- **install-nwchem.sh** - Build and install NWChem (quantum chemistry)
- **install-openblas.sh** - Install OpenBLAS (linear algebra library)
- **install-openmpi.sh** - Install OpenMPI (message passing interface)
- **install-orca.sh** - Install Orca (quantum chemistry) from precompiled binaries
- **install-pmix.sh** - Install PMIx (process management interface)
- **install-spglib.sh** - Build and install Spglib (crystal symmetry operations)
- **install-std2.sh** - Build and install std2 (quantum chemistry)
- **install-ucx.sh** - Build and install UCX (unified communication library)
- **install-xtb.sh** - Install xtb (extended tight-binding) from precompiled binaries
- **install-xtb4stda.sh** - Build and install xtb4stda (ground state for std2) with Intel oneAPI

## Directory Structure

Scripts expect the following directory layout:

```
~/software/
├── src/
│   └── external/              # Source archives and downloaded sources
└── build/
    ├── cfour/VERSION/
    ├── dalton/VERSION-PRECISION/
    ├── dirac/VERSION/
    ├── gpaw/VERSION/
    │   ├── venv/              # Python virtual environment
    │   └── share/             # GPAW data files
    ├── gxtb/VERSION/
    ├── libxc/VERSION/
    ├── molden/VERSION/
    ├── nwchem/VERSION/
    ├── openblas/VERSION-PRECISION/
    ├── openmpi/VERSION-PRECISION/
    │   └── default -> VERSION-PRECISION (symlink)
    ├── orca/VERSION/
    ├── std2/VERSION/
    ├── xtb/VERSION/
    └── xtb4stda/VERSION/
```

Default symlinks (e.g., `openmpi/default`) allow version switching without updating environment variables. The symlink name is configurable via the `SYMLINK_NAME` parameter in each script (default: `default`).
