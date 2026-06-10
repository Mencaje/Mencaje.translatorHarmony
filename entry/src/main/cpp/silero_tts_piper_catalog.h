#ifndef SILERO_TTS_PIPER_CATALOG_H
#define SILERO_TTS_PIPER_CATALOG_H

#include <string>

struct PiperLangVoice {
    const char *iso;
    const char *onnxFile; /* basename under silero_tts/piper/<iso>/ */
};

const PiperLangVoice *PiperCatalogFind(const std::string &iso);
bool PiperCatalogIsGenericLang(const std::string &iso);

#endif
