#include "silero_tts_bridge.h"

#include "silero_tts_inference.h"
#include "silero_tts_sherpa.h"

#include <sys/stat.h>

#include <cstring>
#include <string>
#include <vector>

namespace {

std::string ModelFileNameForIso(const std::string &langIso)
{
    if (langIso == "en") {
        return "v3_en.pt";
    }
    if (langIso == "fr") {
        return "v3_fr.pt";
    }
    if (langIso == "de") {
        return "v3_de.pt";
    }
    if (langIso == "es") {
        return "v3_es.pt";
    }
    if (langIso == "ru") {
        return "v5_cis_base_nostress.jit";
    }
    return "";
}

std::string MobileModelFileNameForIso(const std::string &langIso)
{
    if (langIso == "en") {
        return "v3_en_mobile.ptl";
    }
    return "";
}

std::string JoinPath(const std::string &root, const std::string &name)
{
    if (root.empty()) {
        return name;
    }
    if (root.back() == '/') {
        return root + name;
    }
    return root + "/" + name;
}

bool FileExistsNonEmpty(const std::string &path)
{
    if (path.empty()) {
        return false;
    }
    struct stat st {};
    if (stat(path.c_str(), &st) != 0) {
        return false;
    }
    return S_ISREG(st.st_mode) && st.st_size > 0;
}

} // namespace

bool SileroTtsIsLinked()
{
    return SileroInferenceIsAvailable();
}

std::string SileroTtsBuildInfo()
{
    return SileroInferenceBuildInfo();
}

bool SileroTtsUsesSummerTts()
{
    return SileroInferenceUsesSummerTts();
}

bool SileroTtsUsesPiperPlus()
{
    return SileroInferenceUsesPiperPlus();
}

bool SileroTtsUsesRhvoice()
{
    return SileroInferenceUsesRhvoice();
}

bool SileroTtsIsLangModelPresent(const std::string &modelRoot, const std::string &langIso)
{
    return SileroInferenceIsLangModelPresent(langIso, modelRoot);
}

bool SileroTtsIsAnyModelPresent(const std::string &modelRoot)
{
    static const char *kLangs[] = {"zh", "ja", "en", "fr", "de", "es", "ru"};
    for (const char *lang : kLangs) {
        if (SileroTtsIsLangModelPresent(modelRoot, lang)) {
            return true;
        }
    }
    return false;
}

void SileroTtsCancelSynthesis()
{
    SileroInferenceBumpGeneration();
}

bool SileroTtsSynthesize(uint64_t generationToken,
                         const std::string &langIso,
                         const std::string &text,
                         const std::string &modelRoot,
                         std::vector<int16_t> &pcmOut,
                         int &sampleRateOut,
                         std::string &errOut)
{
    pcmOut.clear();
    sampleRateOut = 0;
    if (text.empty()) {
        errOut = "empty text";
        return false;
    }
    if (!SileroTtsIsLangModelPresent(modelRoot, langIso)) {
        errOut = "Silero model not installed for language";
        return false;
    }
    if (!SileroInferenceIsAvailable()) {
        errOut = "TTS inference not linked: need SummerTTS (zh), piper-plus (ja), and/or Sherpa (en..ru). "
                 "Ensure third_party sources exist and run setup scripts, then Clean+Rebuild.";
        return false;
    }
    return SileroInferenceSynthesize(generationToken, langIso, text, modelRoot, pcmOut, sampleRateOut, errOut);
}
