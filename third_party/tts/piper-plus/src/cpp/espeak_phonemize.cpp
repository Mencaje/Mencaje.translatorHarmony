#include "espeak_phonemize.hpp"

#ifdef PIPER_HAVE_ESPEAK_NG

#include <espeak-ng/speak_lib.h>

#include <mutex>
#include <stdexcept>

namespace piper {

namespace {

std::mutex gEspeakMutex;
bool gEspeakReady = false;
std::string gEspeakDataPath;

} // namespace

bool ensureEspeakInitialized(const std::string &dataPath, std::string &errOut)
{
    if (dataPath.empty()) {
        errOut = "espeak data path empty";
        return false;
    }
    std::lock_guard<std::mutex> lock(gEspeakMutex);
    if (gEspeakReady && gEspeakDataPath == dataPath) {
        return true;
    }
    if (gEspeakReady) {
        espeak_Terminate();
        gEspeakReady = false;
        gEspeakDataPath.clear();
    }
    const int rate = espeak_Initialize(AUDIO_OUTPUT_SYNCHRONOUS, 0, dataPath.c_str(), 0);
    if (rate < 0) {
        errOut = "espeak_Initialize failed: " + dataPath;
        return false;
    }
    gEspeakDataPath = dataPath;
    gEspeakReady = true;
    return true;
}

void phonemizeEspeak(const std::string &text, const std::string &voice,
                     std::vector<std::vector<Phoneme>> &phonemes)
{
    phonemes.clear();
    if (text.empty()) {
        return;
    }
    if (espeak_SetVoiceByName(voice.c_str()) != 0) {
        throw std::runtime_error("espeak_SetVoiceByName failed: " + voice);
    }

    std::string mutableText = text;
    const void *textPtr = mutableText.c_str();
    while (textPtr != nullptr) {
        const char *clause = espeak_TextToPhonemes(
            &textPtr, espeakCHARS_UTF8, 0);
        if (clause == nullptr || clause[0] == '\0') {
            continue;
        }
        phonemes.emplace_back();
        std::vector<Phoneme> &sentence = phonemes.back();
        for (const char *p = clause; *p != '\0'; ++p) {
            sentence.push_back(static_cast<unsigned char>(*p));
        }
    }
    if (phonemes.empty()) {
        phonemes.emplace_back();
    }
}

} // namespace piper

#else

namespace piper {

bool ensureEspeakInitialized(const std::string &, std::string &errOut)
{
    errOut = "espeak-ng not compiled (PIPER_HAVE_ESPEAK_NG)";
    return false;
}

void phonemizeEspeak(const std::string &, const std::string &,
                     std::vector<std::vector<Phoneme>> &phonemes)
{
    phonemes.clear();
}

} // namespace piper

#endif
