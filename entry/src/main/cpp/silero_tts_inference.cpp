/**

 * TTS 推理路由：zh → SummerTTS；ja / Piper 语种 → piper-plus。

 * 已移除 Sherpa-ONNX / Silero(PyTorch) / RHVoice（GPL-2.0）。

 */



#include "silero_tts_inference.h"



#include <atomic>

#include <mutex>

#include <string>

#include <vector>



#include "silero_tts_piperplus.h"

#include "silero_tts_piper_catalog.h"

#include "silero_tts_summertts.h"



namespace {



std::mutex gGlobalSynthMutex;

std::atomic<uint64_t> gSynthGeneration{0};



enum class TtsBackendKind { None = 0, Summer, Piper };



TtsBackendKind gActiveBackend = TtsBackendKind::None;



TtsBackendKind BackendForLang(const std::string &langIso)

{

    if (langIso == "zh") {

        return TtsBackendKind::Summer;

    }

    if (langIso == "ja" || PiperCatalogIsGenericLang(langIso)) {

        return TtsBackendKind::Piper;

    }

    return TtsBackendKind::None;

}



/**
 * 记录当前活跃后端，不在 zh↔Piper 切换时销毁已加载引擎。
 * 避免 cppjieba Trie 析构与 Piper ONNX 堆压力叠加导致间歇性 SIGSEGV。
 */

void PrepareBackend(TtsBackendKind needed)

{

    if (needed == TtsBackendKind::None) {

        return;

    }

    gActiveBackend = needed;

}



} // namespace



uint64_t SileroInferenceBumpGeneration()

{

    return ++gSynthGeneration;

}



uint64_t SileroInferenceCurrentGeneration()

{

    return gSynthGeneration.load(std::memory_order_acquire);

}



bool SileroInferenceIsCancelled(uint64_t generationToken)

{

    return generationToken != gSynthGeneration.load(std::memory_order_acquire);

}



bool SileroInferenceIsAvailable()

{

    return SileroInferenceUsesSummerTts() || SileroInferenceUsesPiperPlus();

}



bool SileroInferenceSynthesize(uint64_t generationToken,

                               const std::string &langIso,

                               const std::string &text,

                               const std::string &modelRoot,

                               std::vector<int16_t> &pcmOut,

                               int &sampleRateOut,

                               std::string &errOut)

{

    std::lock_guard<std::mutex> globalLock(gGlobalSynthMutex);

    if (SileroInferenceIsCancelled(generationToken)) {

        errOut = "synthesis cancelled";

        return false;

    }



    const TtsBackendKind backend = BackendForLang(langIso);

    PrepareBackend(backend);



    bool ok = false;

    if (langIso == "zh") {

        if (!SummerTtsIsAvailable()) {

            errOut = "SummerTTS not linked; rebuild with third_party/tts/SummerTTS present";

            return false;

        }

        if (!SummerTtsIsZhModelPresent(modelRoot)) {

            errOut = "Chinese voice pack not installed (need single_speaker_fast.bin in silero_tts)";

            return false;

        }

        ok = SummerTtsSynthesizeZh(text, modelRoot, pcmOut, sampleRateOut, errOut);

    } else if (langIso == "ja") {

        if (!PiperPlusIsAvailable()) {

            errOut = "piper-plus not linked; rebuild with third_party/tts/piper-plus present";

            return false;

        }

        if (!PiperPlusIsJaModelPresent(modelRoot)) {

            errOut = "Japanese voice pack not installed (piper-plus-ja bundle)";

            return false;

        }

        ok = PiperPlusSynthesizeJa(text, modelRoot, pcmOut, sampleRateOut, errOut);

    } else if (PiperCatalogIsGenericLang(langIso)) {

        if (!PiperPlusIsAvailable()) {

            errOut = "piper-plus not linked; rebuild with third_party/tts/piper-plus present";

            return false;

        }

        if (!PiperPlusIsGenericModelPresent(langIso, modelRoot)) {

            errOut = "Piper voice pack not installed for " + langIso;

            return false;

        }

        ok = PiperPlusSynthesizeGeneric(langIso, text, modelRoot, pcmOut, sampleRateOut, errOut);

    } else {

        errOut = "Unsupported TTS language: " + langIso;

        return false;

    }



    if (ok && SileroInferenceIsCancelled(generationToken)) {

        pcmOut.clear();

        sampleRateOut = 0;

        errOut = "synthesis cancelled";

        return false;

    }

    return ok;

}



bool SileroInferenceIsLangModelPresent(const std::string &langIso, const std::string &modelRoot)

{

    if (langIso == "zh") {

        return SummerTtsIsZhModelPresent(modelRoot);

    }

    if (langIso == "ja") {

        return PiperPlusIsJaModelPresent(modelRoot);

    }

    if (PiperCatalogIsGenericLang(langIso)) {

        return PiperPlusIsGenericModelPresent(langIso, modelRoot);

    }

    return false;

}



bool SileroInferenceUsesSherpaOnnx()

{

    return false;

}



bool SileroInferenceUsesPytorchMobile()

{

    return false;

}



bool SileroInferenceUsesSummerTts()

{

#ifdef SILERO_USE_SUMMERTTS

    return SummerTtsIsAvailable();

#else

    return false;

#endif

}



bool SileroInferenceUsesPiperPlus()

{

#ifdef SILERO_USE_PIPER_PLUS

    return PiperPlusIsAvailable();

#else

    return false;

#endif

}



bool SileroInferenceUsesRhvoice()

{

#ifdef SILERO_USE_RHVOICE

    return RhvoiceIsAvailable();

#else

    return false;

#endif

}



std::string SileroInferenceBuildInfo()

{

    const bool summer = SileroInferenceUsesSummerTts();

    const bool piper = SileroInferenceUsesPiperPlus();

    std::string info;

    if (summer && piper) {

        info = "TTS NAPI + SummerTTS(zh) + piper-plus [summertts+piperplus]";

    } else if (summer) {

        info = "TTS NAPI + SummerTTS Chinese only (zh) [summertts]";

    } else if (piper) {

        info = "TTS NAPI + piper-plus [piperplus]";

    } else {

        info = "TTS NAPI: no native backend linked";

    }

#ifdef SILERO_OHOS_ABI

    info += " abi=";

    info += SILERO_OHOS_ABI;

#endif

    return info;

}


