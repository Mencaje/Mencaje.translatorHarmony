#include "silero_tts_piper_catalog.h"

namespace {

constexpr PiperLangVoice kPiperVoices[] = {
    {"ar", "ar_JO-kareem-medium.onnx"},
    {"ca", "ca_ES-upc_ona-medium.onnx"},
    {"cs", "cs_CZ-jirka-medium.onnx"},
    {"cy", "cy_GB-gwryw_gogleddol-medium.onnx"},
    {"da", "da_DK-talesyntese-medium.onnx"},
    {"de", "de_DE-thorsten-medium.onnx"},
    {"el", "el_GR-rapunzelina-low.onnx"},
    {"en", "en_US-lessac-medium.onnx"},
    {"es", "es_ES-davefx-medium.onnx"},
    {"fa", "fa_IR-ganji-medium.onnx"},
    {"fi", "fi_FI-harri-medium.onnx"},
    {"fr", "fr_FR-siwis-medium.onnx"},
    {"hi", "hi_IN-pratham-medium.onnx"},
    {"hu", "hu_HU-anna-medium.onnx"},
    {"is", "is_IS-salka-medium.onnx"},
    {"it", "it_IT-paola-medium.onnx"},
    {"ka", "ka_GE-natia-medium.onnx"},
    {"kk", "kk_KZ-issai-high.onnx"},
    {"lb", "lb_LU-marylux-medium.onnx"},
    {"lv", "lv_LV-aivars-medium.onnx"},
    {"ml", "ml_IN-meera-medium.onnx"},
    {"ne", "ne_NP-google-medium.onnx"},
    {"nl", "nl_NL-pim-medium.onnx"},
    {"no", "no_NO-talesyntese-medium.onnx"},
    {"pl", "pl_PL-darkman-medium.onnx"},
    {"pt", "pt_BR-faber-medium.onnx"},
    {"ro", "ro_RO-mihai-medium.onnx"},
    {"ru", "ru_RU-denis-medium.onnx"},
    {"sk", "sk_SK-lili-medium.onnx"},
    {"sl", "sl_SI-artur-medium.onnx"},
    {"sr", "sr_RS-serbski_institut-medium.onnx"},
    {"sv", "sv_SE-lisa-medium.onnx"},
    {"sw", "sw_CD-lanfrica-medium.onnx"},
    {"tr", "tr_TR-dfki-medium.onnx"},
    {"uk", "uk_UA-ukrainian_tts-medium.onnx"},
    {"vi", "vi_VN-vais1000-medium.onnx"},
};

} // namespace

const PiperLangVoice *PiperCatalogFind(const std::string &iso)
{
    for (const auto &entry : kPiperVoices) {
        if (iso == entry.iso) {
            return &entry;
        }
    }
    return nullptr;
}

bool PiperCatalogIsGenericLang(const std::string &iso)
{
    return PiperCatalogFind(iso) != nullptr;
}
