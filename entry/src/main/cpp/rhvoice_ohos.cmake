# RHVoice (LGPL-2.1+) — 俄/乌/波/西/葡/格鲁吉亚/吉尔吉斯等

set(RHVOICE_ROOT "${NATIVERENDER_ROOT_PATH}/../../../../third_party/rhvoice")
set(RHVOICE_API_H "${RHVOICE_ROOT}/src/include/RHVoice.h")
if(NOT RHVOICE_LIB_DIR)
    set(RHVOICE_LIB_DIR "${PREBUILT_LIB_DIR}")
endif()
set(RHVOICE_LIB "${RHVOICE_LIB_DIR}/libRHVoice.so")
set(RHVOICE_CORE_LIB "${RHVOICE_LIB_DIR}/libRHVoice_core.so")
if(NOT EXISTS "${RHVOICE_CORE_LIB}")
    set(RHVOICE_CORE_LIB "${RHVOICE_LIB_DIR}/libRHVoice_core.so.1")
endif()

set(SILERO_HAVE_RHVOICE FALSE)
if(EXISTS "${RHVOICE_API_H}"
    AND EXISTS "${RHVOICE_LIB}"
    AND EXISTS "${RHVOICE_CORE_LIB}"
    AND CMAKE_SYSTEM_NAME STREQUAL "OHOS")
    set(SILERO_HAVE_RHVOICE TRUE)
endif()

if(SILERO_HAVE_RHVOICE)
    message(STATUS "Silero TTS: RHVoice enabled (abi=${PYTORCH_ABI})")
endif()
