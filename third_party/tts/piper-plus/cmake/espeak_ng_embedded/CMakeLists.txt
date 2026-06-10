# Minimal espeak-ng static library for Piper phonemization (OHOS cross-compile).
# Runtime loads preinstalled espeak-ng-data from the app bundle — no host-side data compile.

cmake_minimum_required(VERSION 3.15)
project(espeak-ng-embedded C)

if(NOT ESPEAK_NG_ROOT OR NOT EXISTS "${ESPEAK_NG_ROOT}/src/libespeak-ng/speech.c")
  message(FATAL_ERROR "ESPEAK_NG_ROOT must point to espeak-ng source tree")
endif()

set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(USE_ASYNC OFF CACHE BOOL "" FORCE)
set(USE_MBROLA OFF CACHE BOOL "" FORCE)
set(USE_KLATT OFF CACHE BOOL "" FORCE)
set(USE_SPEECHPLAYER OFF CACHE BOOL "" FORCE)
set(USE_LIBPCAUDIO OFF CACHE BOOL "" FORCE)

include("${ESPEAK_NG_ROOT}/cmake/deps.cmake")
include("${ESPEAK_NG_ROOT}/cmake/config.cmake")

add_library(espeak-include INTERFACE)
target_include_directories(espeak-include INTERFACE
  "${ESPEAK_NG_ROOT}/src/include"
  "${ESPEAK_NG_ROOT}/src/include/compat")

add_subdirectory("${ESPEAK_NG_ROOT}/src/ucd-tools" ucd_build)

set(ESPEAK_CONFIG_DIR "${CMAKE_CURRENT_BINARY_DIR}/espeak_config")
set(ESPEAK_CONFIG_H "${ESPEAK_CONFIG_DIR}/config.h")
file(MAKE_DIRECTORY "${ESPEAK_CONFIG_DIR}")
configure_file("${ESPEAK_NG_ROOT}/src/libespeak-ng/config.h.in" "${ESPEAK_CONFIG_H}")

add_library(espeak-ng-config INTERFACE)
target_include_directories(espeak-ng-config INTERFACE "${ESPEAK_CONFIG_DIR}")

add_library(espeak-ng STATIC
  "${ESPEAK_NG_ROOT}/src/libespeak-ng/common.c"
  "${ESPEAK_NG_ROOT}/src/libespeak-ng/mnemonics.c"
  "${ESPEAK_NG_ROOT}/src/libespeak-ng/error.c"
  "${ESPEAK_NG_ROOT}/src/libespeak-ng/ieee80.c"
  "${ESPEAK_NG_ROOT}/src/libespeak-ng/compiledata.c"
  "${ESPEAK_NG_ROOT}/src/libespeak-ng/compiledict.c"
  "${ESPEAK_NG_ROOT}/src/libespeak-ng/dictionary.c"
  "${ESPEAK_NG_ROOT}/src/libespeak-ng/encoding.c"
  "${ESPEAK_NG_ROOT}/src/libespeak-ng/intonation.c"
  "${ESPEAK_NG_ROOT}/src/libespeak-ng/langopts.c"
  "${ESPEAK_NG_ROOT}/src/libespeak-ng/numbers.c"
  "${ESPEAK_NG_ROOT}/src/libespeak-ng/phoneme.c"
  "${ESPEAK_NG_ROOT}/src/libespeak-ng/phonemelist.c"
  "${ESPEAK_NG_ROOT}/src/libespeak-ng/readclause.c"
  "${ESPEAK_NG_ROOT}/src/libespeak-ng/setlengths.c"
  "${ESPEAK_NG_ROOT}/src/libespeak-ng/soundicon.c"
  "${ESPEAK_NG_ROOT}/src/libespeak-ng/spect.c"
  "${ESPEAK_NG_ROOT}/src/libespeak-ng/ssml.c"
  "${ESPEAK_NG_ROOT}/src/libespeak-ng/synthdata.c"
  "${ESPEAK_NG_ROOT}/src/libespeak-ng/synthesize.c"
  "${ESPEAK_NG_ROOT}/src/libespeak-ng/tr_languages.c"
  "${ESPEAK_NG_ROOT}/src/libespeak-ng/translate.c"
  "${ESPEAK_NG_ROOT}/src/libespeak-ng/translateword.c"
  "${ESPEAK_NG_ROOT}/src/libespeak-ng/voices.c"
  "${ESPEAK_NG_ROOT}/src/libespeak-ng/wavegen.c"
  "${ESPEAK_NG_ROOT}/src/libespeak-ng/speech.c"
  "${ESPEAK_NG_ROOT}/src/libespeak-ng/espeak_api.c"
)

set_target_properties(espeak-ng PROPERTIES POSITION_INDEPENDENT_CODE ON)

target_include_directories(espeak-ng PRIVATE
  "${ESPEAK_NG_ROOT}/src/include"
  "${ESPEAK_NG_ROOT}/src/include/compat"
  "${ESPEAK_NG_ROOT}/src/ucd-tools/src/include")

if(NOT MSVC)
  target_compile_options(espeak-ng PRIVATE
    -fPIC
    -fvisibility=hidden
    -fno-exceptions
    -fwrapv
    -Wno-unused-parameter
    -Wno-unused
    -Wno-missing-prototypes)
endif()

target_compile_definitions(espeak-ng PRIVATE LIBESPEAK_NG_EXPORT=1)
target_compile_definitions(espeak-ng PRIVATE
  "PATH_ESPEAK_DATA=\"${CMAKE_INSTALL_PREFIX}/share/espeak-ng-data\"")

if(HAVE_LIBSONIC AND USE_LIBSONIC)
  target_link_libraries(espeak-ng PRIVATE ${SONIC_LIB})
  target_include_directories(espeak-ng PRIVATE ${SONIC_INC})
endif()

target_link_libraries(espeak-ng PRIVATE espeak-ng-config ucd)
if(NOT MSVC)
  target_link_libraries(espeak-ng PRIVATE m)
endif()
# Do not PUBLIC-link espeak-include: compat/wchar.h poisons C++ std::tolower in other TUs.
