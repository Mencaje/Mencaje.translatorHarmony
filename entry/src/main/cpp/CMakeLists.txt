# CTranslate2 NAPI 桥接（HarmonyOS）
# silero_tts_napi：zh=SummerTTS，ja + Piper 语种=piper-plus（已剔除 RHVoice GPL-2.0）

cmake_minimum_required(VERSION 3.16)
project(ctranslate2_napi)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

include_directories(${NATIVERENDER_ROOT_PATH})

add_library(ctranslate2_napi SHARED
    napi_init.cpp
    ctranslate2_bridge.cpp
)

target_link_libraries(ctranslate2_napi PUBLIC libace_napi.z.so)

include("${NATIVERENDER_ROOT_PATH}/ctranslate2_ohos.cmake")

set(SILERO_SOURCES
    silero_napi_init.cpp
    silero_tts_bridge.cpp
    silero_tts_inference.cpp
    silero_tts_summertts.cpp
    silero_tts_piperplus.cpp
    silero_tts_piper_catalog.cpp
)

set(SUMMERTTS_ROOT "${NATIVERENDER_ROOT_PATH}/../../../../third_party/tts/SummerTTS")
set(SUMMERTTS_SYNTH_CPP "${SUMMERTTS_ROOT}/src/models/SynthesizerTrn.cpp")
set(SILERO_HAVE_SUMMERTTS FALSE)
if(EXISTS "${SUMMERTTS_SYNTH_CPP}")
    set(SILERO_HAVE_SUMMERTTS TRUE)
    include("${NATIVERENDER_ROOT_PATH}/summertts_sources.cmake")
    list(APPEND SILERO_SOURCES ${SUMMERTTS_CPP_SOURCES})
endif()

set(ORT_ROOT "${NATIVERENDER_ROOT_PATH}/../../../../third_party/ohos/onnxruntime")
set(PYTORCH_ABI "${OHOS_ARCH}")
if(NOT PYTORCH_ABI)
    set(PYTORCH_ABI "${CMAKE_OHOS_ARCH_ABI}")
endif()
set(ENTRY_MODULE_LIBS_DIR "${NATIVERENDER_ROOT_PATH}/../../../libs/${PYTORCH_ABI}")
set(ENTRY_SRC_MAIN_LIBS_DIR "${NATIVERENDER_ROOT_PATH}/../libs/${PYTORCH_ABI}")
add_library(silero_tts_napi SHARED ${SILERO_SOURCES})

target_link_libraries(silero_tts_napi PUBLIC libace_napi.z.so)
target_compile_definitions(silero_tts_napi PRIVATE "SILERO_OHOS_ABI=\"${PYTORCH_ABI}\"")
set(ORT_PREBUILT_PER_ABI "${ORT_ROOT}/prebuilt/${PYTORCH_ABI}/libonnxruntime.so")
if(EXISTS "${ORT_PREBUILT_PER_ABI}")
    set(ORT_PREBUILT_LIB "${ORT_PREBUILT_PER_ABI}")
else()
    set(ORT_PREBUILT_LIB "")
endif()

include("${NATIVERENDER_ROOT_PATH}/piperplus_ohos.cmake")

if(SILERO_HAVE_SUMMERTTS OR SILERO_HAVE_PIPERPLUS)
    set_target_properties(silero_tts_napi PROPERTIES CXX_STANDARD 17 CXX_STANDARD_REQUIRED ON)
endif()

if(SILERO_HAVE_SUMMERTTS)
    message(STATUS "Silero TTS: SummerTTS Chinese enabled")
    target_compile_definitions(silero_tts_napi PRIVATE SILERO_USE_SUMMERTTS)
    target_include_directories(silero_tts_napi PRIVATE
        ${SUMMERTTS_ROOT}/eigen-3.4.0
        ${SUMMERTTS_ROOT}/include
        ${SUMMERTTS_ROOT}/src/header
        ${SUMMERTTS_ROOT}/src/tn/header
    )
    set(SUMMERTTS_OHOS_COMPAT "${NATIVERENDER_ROOT_PATH}/summertts_ohos_compat.h")
    target_compile_options(silero_tts_napi PRIVATE -O2 -w
        "-include${SUMMERTTS_OHOS_COMPAT}")
endif()

if(SILERO_HAVE_PIPERPLUS)
    message(STATUS "Silero TTS: piper-plus Japanese enabled")
    target_compile_definitions(silero_tts_napi PRIVATE SILERO_USE_PIPER_PLUS)
    target_include_directories(silero_tts_napi PRIVATE ${PIPERPLUS_ROOT}/src/cpp)
    target_link_libraries(silero_tts_napi PRIVATE piper_plus)
    if(EXISTS "${ORT_PREBUILT_LIB}")
        add_custom_command(TARGET silero_tts_napi POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                "${ORT_PREBUILT_LIB}" "$<TARGET_FILE_DIR:silero_tts_napi>/libonnxruntime.so"
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                "$<TARGET_FILE_DIR:piper_plus>/libpiper_plus.so"
                "$<TARGET_FILE_DIR:silero_tts_napi>/libpiper_plus.so"
            COMMENT "Copy onnxruntime + libpiper_plus beside libsilero_tts_napi.so"
        )
    else()
        add_custom_command(TARGET silero_tts_napi POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                "$<TARGET_FILE_DIR:piper_plus>/libpiper_plus.so"
                "$<TARGET_FILE_DIR:silero_tts_napi>/libpiper_plus.so"
            COMMENT "Copy libpiper_plus beside libsilero_tts_napi.so"
        )
    endif()
endif()

if(NOT SILERO_HAVE_SUMMERTTS AND NOT SILERO_HAVE_PIPERPLUS)
    message(WARNING "TTS: no backend — run scripts/prepare_native_tts.ps1 (SummerTTS / piper-plus)")
endif()
