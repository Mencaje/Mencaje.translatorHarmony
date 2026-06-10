# piper-plus (MIT) — 日语 TTS，在 OHOS 工具链下编译 libpiper_plus.so

set(PIPERPLUS_ROOT "${NATIVERENDER_ROOT_PATH}/../../../../third_party/tts/piper-plus")
set(PIPERPLUS_API_H "${PIPERPLUS_ROOT}/src/cpp/piper_plus.h")
set(ORT_ROOT "${NATIVERENDER_ROOT_PATH}/../../../../third_party/ohos/onnxruntime")

set(SILERO_HAVE_PIPERPLUS FALSE)
# 日语 piper-plus：arm64-v8a 与 x86_64 均编入（需对应 ABI 的 libonnxruntime.so）
set(_piper_ohos_abi "${OHOS_ARCH}")
if(NOT _piper_ohos_abi)
    set(_piper_ohos_abi "${CMAKE_OHOS_ARCH_ABI}")
endif()
# ONNX Runtime 按 ABI 放在 third_party/ohos/onnxruntime/prebuilt/<abi>/（勿复制到 entry/libs）
set(_ort_for_piper "")
set(_ort_prebuilt_abi "${ORT_ROOT}/prebuilt/${_piper_ohos_abi}/libonnxruntime.so")
if(EXISTS "${_ort_prebuilt_abi}")
    set(_ort_for_piper "${_ort_prebuilt_abi}")
elseif(DEFINED ORT_PREBUILT_LIB AND EXISTS "${ORT_PREBUILT_LIB}")
    set(_ort_for_piper "${ORT_PREBUILT_LIB}")
endif()

if(EXISTS "${PIPERPLUS_API_H}"
    AND CMAKE_SYSTEM_NAME STREQUAL "OHOS"
    AND (_piper_ohos_abi STREQUAL "arm64-v8a" OR _piper_ohos_abi STREQUAL "x86_64")
    AND EXISTS "${_ort_for_piper}"
    AND EXISTS "${ORT_ROOT}/include/onnxruntime_c_api.h")
    set(SILERO_HAVE_PIPERPLUS TRUE)
endif()

if(SILERO_HAVE_PIPERPLUS)
    set(BUILD_TESTS OFF CACHE BOOL "" FORCE)
    set(PIPER_PLUS_BUILD_SHARED ON CACHE BOOL "" FORCE)
    # ProcessLibs 不允许同模块内 libpiper_plus.so + libpiper_plus.so.1；勿用 VERSION=""（会破坏 TARGET_FILE 路径）
    set(PIPER_OHOS_NO_SONAME ON CACHE BOOL "" FORCE)
    set(PIPER_OHOS_BUILD ON CACHE BOOL "" FORCE)

    set(_espeak_ng_root "${PIPERPLUS_ROOT}/../../../Mencaje.translator/third_party/espeak-ng")
    get_filename_component(_espeak_ng_root "${_espeak_ng_root}" ABSOLUTE)
    if(EXISTS "${_espeak_ng_root}/CMakeLists.txt")
        set(ESPEAK_NG_ROOT "${_espeak_ng_root}" CACHE PATH "espeak-ng source for Piper espeak voices" FORCE)
        message(STATUS "Silero TTS: espeak-ng root ${ESPEAK_NG_ROOT}")
    else()
        message(WARNING "Silero TTS: espeak-ng not found at ${_espeak_ng_root} — Piper ar/de voices need native rebuild after vendor")
    endif()

    set(ONNXRUNTIME_DIR "${ORT_ROOT}")
    set(ONNXRUNTIME_INCLUDE_DIR "${ORT_ROOT}/include")
    # 按 ABI 链接 prebuilt/<abi>/libonnxruntime.so，勿写入共享 lib/（并行编 arm/x86 会互相覆盖）
    set(ONNXRUNTIME_LIB "${_ort_for_piper}")

    set(_ohos_native "${OHOS_SDK_NATIVE}")
    if(NOT _ohos_native)
        set(_ohos_native "$ENV{OHOS_SDK_NATIVE}")
    endif()
    set(_hmos_native "${HMOS_SDK_NATIVE}")
    if(NOT _hmos_native)
        set(_hmos_native "$ENV{HMOS_SDK_NATIVE}")
    endif()
    # ExternalProject / try_compile 须用 openharmony 的 ohos.toolchain；hmos.toolchain 在子工程会找不到 ohos.toolchain
    set(_ohos_toolchain "")
    if(_ohos_native AND EXISTS "${_ohos_native}/build/cmake/ohos.toolchain.cmake")
        set(_ohos_toolchain "${_ohos_native}/build/cmake/ohos.toolchain.cmake")
    elseif(CMAKE_TOOLCHAIN_FILE AND EXISTS "${CMAKE_TOOLCHAIN_FILE}")
        set(_ohos_toolchain "${CMAKE_TOOLCHAIN_FILE}")
    elseif(_hmos_native AND EXISTS "${_hmos_native}/build/cmake/hmos.toolchain.cmake")
        set(_ohos_toolchain "${_hmos_native}/build/cmake/hmos.toolchain.cmake")
    endif()

    set(EXTERNAL_CMAKE_ARGS
        -DCMAKE_TOOLCHAIN_FILE=${_ohos_toolchain}
        -DOHOS_SDK_NATIVE=${_ohos_native}
        -DHMOS_SDK_NATIVE=${_hmos_native}
        -DCMAKE_MAKE_PROGRAM=${CMAKE_MAKE_PROGRAM}
        -DCMAKE_SYSTEM_NAME=OHOS
        -DOHOS_ARCH=${_piper_ohos_abi}
        -DCMAKE_OHOS_ARCH_ABI=${_piper_ohos_abi}
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY
    )

    add_subdirectory("${PIPERPLUS_ROOT}" "${CMAKE_BINARY_DIR}/piper_plus_build")
endif()
