/**
 * Silero v3 多语种：从 torch.package（v3_*.pt）本机合成。
 * 需 SILERO_USE_PYTORCH_MOBILE 且链接 libpytorch_ohos.so。
 */

#include "silero_tts_inference.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstring>
#include <string>
#include <vector>

#ifdef SILERO_USE_PYTORCH_MOBILE

#include <torch/csrc/jit/api.h>
#include <torch/csrc/jit/mobile/import.h>
#include <torch/script.h>
#include <ATen/ATen.h>

namespace {

constexpr int kSampleRate = 48000;
constexpr int kDefaultSpeakerId = 0;
constexpr float kDefaultSpeed = 1.0f;

static std::string ModelFileNameForIso(const std::string &iso)
{
    if (iso == "en") {
        return "v3_en.pt";
    }
    if (iso == "fr") {
        return "v3_fr.pt";
    }
    if (iso == "de") {
        return "v3_de.pt";
    }
    if (iso == "es") {
        return "v3_es.pt";
    }
    if (iso == "ru") {
        return "v5_cis_base_nostress.jit";
    }
    return "";
}

static bool IsAsciiLetter(unsigned char c)
{
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}

static bool IsLatin1Letter(unsigned char c)
{
    if (IsAsciiLetter(c)) {
        return true;
    }
    const unsigned char u = c;
    if (u >= 0xC0 && u <= 0xFF) {
        return true;
    }
    return false;
}

static bool IsCyrillicUtf8(const std::string &s, size_t i, size_t &adv)
{
    adv = 1;
    const unsigned char c0 = static_cast<unsigned char>(s[i]);
    if (c0 < 0xD0 || c0 > 0xDF || i + 1 >= s.size()) {
        return false;
    }
    const unsigned char c1 = static_cast<unsigned char>(s[i + 1]);
    if (c1 < 0x80 || c1 > 0xBF) {
        return false;
    }
    adv = 2;
    return true;
}

static std::string PrepareTextForLang(const std::string &langIso, const std::string &text)
{
    std::string out;
    out.reserve(text.size());
    const bool latin = (langIso == "fr" || langIso == "de" || langIso == "es");
    const bool cyrillic = (langIso == "ru");

    for (size_t i = 0; i < text.size();) {
        const unsigned char c = static_cast<unsigned char>(text[i]);
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
            out.push_back(static_cast<char>(c));
            i++;
            continue;
        }
        if (langIso == "en" || latin) {
            if (IsAsciiLetter(c)) {
                out.push_back(static_cast<char>(std::tolower(c)));
                i++;
                continue;
            }
            if (latin && IsLatin1Letter(c)) {
                out.push_back(static_cast<char>(c));
                i++;
                continue;
            }
            i++;
            continue;
        }
        if (cyrillic) {
            size_t adv = 1;
            if (IsCyrillicUtf8(text, i, adv)) {
                for (size_t k = 0; k < adv; k++) {
                    out.push_back(text[i + k]);
                }
                i += adv;
                continue;
            }
            if (c < 0x80) {
                out.push_back(static_cast<char>(c));
            }
            i++;
            continue;
        }
        i++;
    }
    return out;
}

static bool LoadSileroModuleFromPackage(const std::string &path, torch::jit::Module &moduleOut, std::string &errOut)
{
    try {
        torch::jit::PackageImporter importer(path);
        c10::IValue loaded = importer.load_pickle("tts_models", "model");
        if (loaded.isObject()) {
            auto obj = loaded.toObject();
            if (obj->hasattr("model")) {
                moduleOut = obj->getattr("model").toModule();
                return true;
            }
            try {
                moduleOut = obj->toModule();
                return true;
            } catch (...) {
            }
        }
        if (loaded.isModule()) {
            moduleOut = loaded.toModule();
            return true;
        }
        errOut = "package pickle is not a torch module";
        return false;
    } catch (const std::exception &e) {
        errOut = std::string("PackageImporter: ") + e.what();
        return false;
    } catch (...) {
        errOut = "PackageImporter failed";
        return false;
    }
}

static bool LoadSileroModule(const std::string &path, torch::jit::Module &moduleOut, std::string &errOut)
{
    if (LoadSileroModuleFromPackage(path, moduleOut, errOut)) {
        return true;
    }
    try {
        moduleOut = torch::jit::load(path);
        moduleOut.eval();
        return true;
    } catch (const std::exception &e) {
        errOut = std::string("jit::load: ") + e.what();
        return false;
    } catch (...) {
        errOut = "jit::load failed";
        return false;
    }
}

static bool TensorToPcm16(const at::Tensor &audio, std::vector<int16_t> &pcmOut, std::string &errOut)
{
    if (!audio.defined() || audio.numel() == 0) {
        errOut = "empty audio tensor";
        return false;
    }
    at::Tensor flat = audio;
    if (flat.dim() > 1) {
        flat = flat.reshape({-1});
    }
    flat = flat.to(torch::kCPU).to(torch::kFloat);
    const int64_t n = flat.numel();
    pcmOut.resize(static_cast<size_t>(n));
    const float *src = flat.data_ptr<float>();
    for (int64_t i = 0; i < n; i++) {
        float v = src[i];
        if (!std::isfinite(v)) {
            v = 0.0f;
        }
        v = std::max(-1.0f, std::min(1.0f, v));
        pcmOut[static_cast<size_t>(i)] =
            static_cast<int16_t>(std::lround(v * 32767.0f));
    }
    return !pcmOut.empty();
}

static bool PytorchSileroSynthesize(const std::string &langIso,
                                    const std::string &text,
                                    const std::string &modelRoot,
                                    std::vector<int16_t> &pcmOut,
                                    int &sampleRateOut,
                                    std::string &errOut)
{
    const std::string fileName = ModelFileNameForIso(langIso);
    if (fileName.empty()) {
        errOut = "unsupported language for PyTorch Silero";
        return false;
    }
    std::string root = modelRoot;
    if (!root.empty() && root.back() != '/') {
        root += '/';
    }
    const std::string modelPath = root + fileName;

    torch::jit::Module module;
    if (!LoadSileroModule(modelPath, module, errOut)) {
        return false;
    }
    module.eval();

    const std::string sentence = PrepareTextForLang(langIso, text);
    if (sentence.empty()) {
        errOut = "empty text after normalization";
        return false;
    }

    try {
        c10::List<c10::string> sentences;
        sentences.push_back(sentence);
        c10::List<c10::string> cleanSentences;
        cleanSentences.push_back(sentence);

        const int64_t speakerId = kDefaultSpeakerId;
        const double speed = static_cast<double>(kDefaultSpeed);

        std::vector<torch::jit::IValue> inputs;
        inputs.emplace_back(sentences);
        inputs.emplace_back(speakerId);
        inputs.emplace_back(speed);
        inputs.emplace_back(cleanSentences);

        auto out = module.forward(inputs);
        at::Tensor audio;
        if (out.isTensor()) {
            audio = out.toTensor();
        } else if (out.isTuple()) {
            auto tup = out.toTuple();
            if (tup->elements().empty() || !tup->elements()[0].isTensor()) {
                errOut = "unexpected tuple output from Silero model";
                return false;
            }
            audio = tup->elements()[0].toTensor();
        } else if (out.isList()) {
            auto lst = out.toList();
            if (lst.size() == 0 || !lst.get(0).isTensor()) {
                errOut = "unexpected list output from Silero model";
                return false;
            }
            audio = lst.get(0).toTensor();
        } else {
            errOut = "unexpected output type from Silero forward";
            return false;
        }

        if (!TensorToPcm16(audio, pcmOut, errOut)) {
            return false;
        }
        sampleRateOut = kSampleRate;
        return true;
    } catch (const std::exception &e) {
        errOut = std::string("Silero forward: ") + e.what();
        return false;
    } catch (...) {
        errOut = "Silero forward failed";
        return false;
    }
}

} // namespace

bool SileroPytorchSynthesize(const std::string &langIso,
                             const std::string &text,
                             const std::string &modelRoot,
                             std::vector<int16_t> &pcmOut,
                             int &sampleRateOut,
                             std::string &errOut)
{
    return PytorchSileroSynthesize(langIso, text, modelRoot, pcmOut, sampleRateOut, errOut);
}

#endif // SILERO_USE_PYTORCH_MOBILE
