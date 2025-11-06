# FindSpglib.cmake - Find the Spglib library
#
# This module defines:
#   Spglib_FOUND - whether spglib was found
#   Spglib_INCLUDE_DIRS - include directories for spglib
#   Spglib_LIBRARIES - libraries to link
#
# Set Spglib_DIR to the spglib installation directory

find_path(Spglib_INCLUDE_DIR
  NAMES spglib.h
  HINTS ${Spglib_DIR} ${CMAKE_PREFIX_PATH}
  PATH_SUFFIXES include
)

find_library(Spglib_LIBRARY
  NAMES symspacegroup spglib
  HINTS ${Spglib_DIR} ${CMAKE_PREFIX_PATH}
  PATH_SUFFIXES lib lib64
)

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(Spglib
  REQUIRED_VARS Spglib_LIBRARY Spglib_INCLUDE_DIR
)

if(Spglib_FOUND)
  set(Spglib_INCLUDE_DIRS ${Spglib_INCLUDE_DIR})
  set(Spglib_LIBRARIES ${Spglib_LIBRARY})

  if(NOT TARGET Spglib::Spglib)
    add_library(Spglib::Spglib UNKNOWN IMPORTED)
    set_target_properties(Spglib::Spglib PROPERTIES
      IMPORTED_LOCATION "${Spglib_LIBRARY}"
      INTERFACE_INCLUDE_DIRECTORIES "${Spglib_INCLUDE_DIRS}"
    )
  endif()
endif()

mark_as_advanced(Spglib_INCLUDE_DIR Spglib_LIBRARY)
