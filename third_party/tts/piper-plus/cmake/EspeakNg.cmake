# espeak-ng static library for OHOS Piper espeak voices (ar, de, ...)

if(NOT PIPER_OHOS_BUILD)
  return()
endif()

if(DEFINED ESPEAK_NG_ROOT)
  set(_espeak_root "${ESPEAK_NG_ROOT}")
else()
  get_filename_component(_piper_plus_root "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
  set(_espeak_candidates
    "${_piper_plus_root}/../../../Mencaje.translator/third_party/espeak-ng"
    "${_piper_plus_root}/../../../../Mencaje.translator/third_party/espeak-ng"
  )
  set(_espeak_root "")
  foreach(_cand IN LISTS _espeak_candidates)
    get_filename_component(_cand_abs "${_cand}" ABSOLUTE)
    if(EXISTS "${_cand_abs}/CMakeLists.txt")
      set(_espeak_root "${_cand_abs}")
      break()
    endif()
  endforeach()
endif()

if(NOT _espeak_root OR NOT EXISTS "${_espeak_root}/src/libespeak-ng/speech.c")
  message(WARNING "piper-plus: espeak-ng not found — Piper espeak voices disabled (set ESPEAK_NG_ROOT)")
  return()
endif()

# Full espeak-ng CMake runs espeak-ng-bin on the build host to compile dictionaries;
# that breaks OHOS cross-compile. Use embedded lib-only target instead.
set(ESPEAK_NG_ROOT "${_espeak_root}" CACHE PATH "espeak-ng source root" FORCE)
add_subdirectory("${CMAKE_CURRENT_LIST_DIR}/espeak_ng_embedded" "${CMAKE_BINARY_DIR}/espeak_ng_build")

target_compile_definitions(piper_common PRIVATE PIPER_HAVE_ESPEAK_NG=1)
get_filename_component(_espeak_phon_src "${CMAKE_CURRENT_LIST_DIR}/../src/cpp/espeak_phonemize.cpp" ABSOLUTE)
set_source_files_properties("${_espeak_phon_src}" PROPERTIES
  INCLUDE_DIRECTORIES "${_espeak_root}/src/include;${_espeak_root}/src/include/compat;${_espeak_root}/src/ucd-tools/src/include"
  COMPILE_DEFINITIONS "LIBESPEAK_NG_EXPORT=1"
)
target_link_libraries(piper_common PRIVATE espeak-ng)

if(TARGET piper_plus)
  target_link_libraries(piper_plus PRIVATE espeak-ng)
endif()

message(STATUS "piper-plus: linked espeak-ng (embedded) from ${_espeak_root}")
