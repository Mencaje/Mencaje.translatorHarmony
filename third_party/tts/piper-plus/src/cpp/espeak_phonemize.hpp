#ifndef PIPER_ESPEAK_PHONEMIZE_HPP_
#define PIPER_ESPEAK_PHONEMIZE_HPP_

#include <string>
#include <vector>

#include "phoneme_ids.hpp"

namespace piper {

bool ensureEspeakInitialized(const std::string &dataPath, std::string &errOut);

void phonemizeEspeak(const std::string &text, const std::string &voice,
                     std::vector<std::vector<Phoneme>> &phonemes);

} // namespace piper

#endif
