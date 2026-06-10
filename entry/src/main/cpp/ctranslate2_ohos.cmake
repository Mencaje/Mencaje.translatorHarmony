# CTranslate2 + SentencePiece for HarmonyOS (prebuilt libctranslate2.so + static sentencepiece)

set(CT2_ROOT "${NATIVERENDER_ROOT_PATH}/../../../../CTranslate2")
set(SPM_ROOT "${NATIVERENDER_ROOT_PATH}/../../../../third_party/sentencepiece")

if(NOT PYTORCH_ABI)
    set(PYTORCH_ABI "${CMAKE_OHOS_ARCH_ABI}")
endif()

set(CT2_LIB_DIR "${NATIVERENDER_ROOT_PATH}/../../../libs/${PYTORCH_ABI}")
if(NOT EXISTS "${CT2_LIB_DIR}/libctranslate2.so")
    set(CT2_LIB_DIR "${NATIVERENDER_ROOT_PATH}/../libs/${PYTORCH_ABI}")
endif()

set(CT2_LIB "${CT2_LIB_DIR}/libctranslate2.so")
set(SPM_STATIC "${CT2_LIB_DIR}/libsentencepiece.a")

set(MENCAJE_HAVE_CT2 FALSE)
if(CMAKE_SYSTEM_NAME STREQUAL "OHOS"
    AND EXISTS "${CT2_ROOT}/include/ctranslate2/translator.h"
    AND EXISTS "${CT2_LIB}"
    AND EXISTS "${SPM_ROOT}/src/sentencepiece_processor.h"
    AND EXISTS "${SPM_STATIC}")
    set(MENCAJE_HAVE_CT2 TRUE)
endif()

if(MENCAJE_HAVE_CT2)
    message(STATUS "CTranslate2 NAPI: linked libctranslate2 + sentencepiece (abi=${PYTORCH_ABI})")
    target_compile_definitions(ctranslate2_napi PRIVATE
        MENCAJE_CT2_LINKED=1
        "MENCAJE_CT2_ABI=\"${PYTORCH_ABI}\""
    )
    target_include_directories(ctranslate2_napi PRIVATE
        ${CT2_ROOT}/include
        ${SPM_ROOT}/src
        ${SPM_ROOT}/third_party/absl
    )
    target_link_directories(ctranslate2_napi PRIVATE ${CT2_LIB_DIR})
    target_link_libraries(ctranslate2_napi PRIVATE ctranslate2 sentencepiece)
    set_target_properties(ctranslate2_napi PROPERTIES CXX_STANDARD 17 CXX_STANDARD_REQUIRED ON)
    # Prebuilt libctranslate2*.so live in entry/libs/${abi}/ and are packaged from there.
    # Do not POST_BUILD-copy beside libctranslate2_napi.so — hvigor ProcessLibs rejects duplicates.
else()
    message(WARNING "CTranslate2 offline: missing lib or sentencepiece — run scripts/build_ctranslate2_ohos.ps1 and build_sentencepiece_ohos.ps1")
    target_compile_definitions(ctranslate2_napi PRIVATE "MENCAJE_CT2_ABI=\"${PYTORCH_ABI}\"")
endif()
