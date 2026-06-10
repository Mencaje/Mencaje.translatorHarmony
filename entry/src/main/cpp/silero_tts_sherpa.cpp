#include "silero_tts_sherpa.h"

#include <sys/stat.h>

#include <cmath>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#if defined(SILERO_USE_SHERPA_ONNX)

#include "sherpa-onnx/c-api/c-api.h"

#endif

namespace {

constexpr char kEnSherpaDir[] = "vits-piper-en_US-lessac-low";
constexpr char kEnOnnxName[] = "en_US-lessac-low.onnx";
constexpr char kFrSherpaDir[] = "vits-piper-fr_FR-siwis-low";
constexpr char kFrOnnxName[] = "fr_FR-siwis-low.onnx";
constexpr char kDeSherpaDir[] = "vits-piper-de_DE-thorsten-low";
constexpr char kDeOnnxName[] = "de_DE-thorsten-low.onnx";
constexpr char kEsSherpaDir[] = "vits-piper-es_ES-carlfm-x_low";
constexpr char kEsOnnxName[] = "es_ES-carlfm-x_low.onnx";
constexpr char kRuSherpaDir[] = "vits-piper-ru_RU-ruslan-medium";
constexpr char kRuOnnxName[] = "ru_RU-ruslan-medium.onnx";
constexpr char kTokensName[] = "tokens.txt";
constexpr char kEspeakDir[] = "espeak-ng-data";

struct SherpaLangConfig {
    const char *iso;
    const char *bundleDir;
    const char *onnxName;
};

#if defined(SILERO_USE_SHERPA_ONNX)
constexpr SherpaLangConfig kSherpaLangs[] = {
    {"en", kEnSherpaDir, kEnOnnxName},
    {"fr", kFrSherpaDir, kFrOnnxName},
    {"de", kDeSherpaDir, kDeOnnxName},
    {"es", kEsSherpaDir, kEsOnnxName},
    {"ru", kRuSherpaDir, kRuOnnxName},
};
#endif

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

bool DirExists(const std::string &path)
{
    if (path.empty()) {
        return false;
    }
    struct stat st {};
    if (stat(path.c_str(), &st) != 0) {
        return false;
    }
    return S_ISDIR(st.st_mode);
}

#if defined(SILERO_USE_SHERPA_ONNX)

const SherpaLangConfig *ConfigForIso(const std::string &langIso)
{
    for (const auto &cfg : kSherpaLangs) {
        if (langIso == cfg.iso) {
            return &cfg;
        }
    }
    return nullptr;
}

std::string BundleDirForLang(const std::string &modelRoot, const SherpaLangConfig &cfg)
{
    return JoinPath(modelRoot, cfg.bundleDir);
}

std::mutex gTtsMutex;
const SherpaOnnxOfflineTts *gTts = nullptr;
std::string gLoadedBundleDir;

void DestroyTtsLocked()
{
    if (gTts != nullptr) {
        SherpaOnnxDestroyOfflineTts(gTts);
        gTts = nullptr;
    }
    gLoadedBundleDir.clear();
}

bool EnsureTts(const std::string &bundleDir, const char *onnxName, std::string &errOut)
{
    std::lock_guard<std::mutex> lock(gTtsMutex);
    if (gTts != nullptr && gLoadedBundleDir == bundleDir) {
        return true;
    }
    DestroyTtsLocked();

    const std::string onnxFile = JoinPath(bundleDir, onnxName);
    const std::string tokensPath = JoinPath(bundleDir, kTokensName);
    const std::string dataDir = JoinPath(bundleDir, kEspeakDir);
    if (!FileExistsNonEmpty(onnxFile) || !FileExistsNonEmpty(tokensPath) || !DirExists(dataDir)) {
        errOut = "Sherpa Piper bundle incomplete under " + bundleDir;
        return false;
    }

    SherpaOnnxOfflineTtsConfig config {};
    config.model.num_threads = 2;
    config.model.debug = 0;
    config.model.provider = "cpu";
    config.model.vits.model = onnxFile.c_str();
    config.model.vits.tokens = tokensPath.c_str();
    config.model.vits.data_dir = dataDir.c_str();
    config.model.vits.noise_scale = 0.667f;
    config.model.vits.noise_scale_w = 0.8f;
    config.model.vits.length_scale = 1.0f;
    config.max_num_sentences = 1;

    gTts = SherpaOnnxCreateOfflineTts(&config);
    if (gTts == nullptr) {
        errOut = "SherpaOnnxCreateOfflineTts failed";
        return false;
    }
    gLoadedBundleDir = bundleDir;
    return true;
}

#endif

} // namespace

bool SherpaInferenceIsAvailable()
{
#if defined(SILERO_USE_SHERPA_ONNX)
    return true;
#else
    return false;
#endif
}

bool SherpaInferenceIsModelPresent(const std::string &modelRoot, const std::string &langIso)
{
#if !defined(SILERO_USE_SHERPA_ONNX)
    (void)modelRoot;
    (void)langIso;
    return false;
#else
    const SherpaLangConfig *cfg = ConfigForIso(langIso);
    if (cfg == nullptr) {
        return false;
    }
    const std::string bundle = BundleDirForLang(modelRoot, *cfg);
    return FileExistsNonEmpty(JoinPath(bundle, cfg->onnxName)) &&
           FileExistsNonEmpty(JoinPath(bundle, kTokensName)) &&
           DirExists(JoinPath(bundle, kEspeakDir));
#endif
}

bool SherpaInferenceSynthesize(const std::string &langIso,
                               const std::string &text,
                               const std::string &modelRoot,
                               std::vector<int16_t> &pcmOut,
                               int &sampleRateOut,
                               std::string &errOut)
{
    pcmOut.clear();
    sampleRateOut = 0;
#if !defined(SILERO_USE_SHERPA_ONNX)
    (void)langIso;
    (void)text;
    (void)modelRoot;
    errOut = "Sherpa-ONNX not linked in this build";
    return false;
#else
    const SherpaLangConfig *cfg = ConfigForIso(langIso);
    if (cfg == nullptr) {
        errOut = "Sherpa backend does not support language: " + langIso;
        return false;
    }
    if (text.empty()) {
        errOut = "empty text";
        return false;
    }
    const std::string bundle = BundleDirForLang(modelRoot, *cfg);
    if (!SherpaInferenceIsModelPresent(modelRoot, langIso)) {
        errOut = "Sherpa Piper voice bundle not installed for " + langIso;
        return false;
    }
    if (!EnsureTts(bundle, cfg->onnxName, errOut)) {
        return false;
    }

    std::lock_guard<std::mutex> lock(gTtsMutex);
    if (gTts == nullptr) {
        errOut = "TTS engine not initialized";
        return false;
    }

    const SherpaOnnxGeneratedAudio *audio =
        SherpaOnnxOfflineTtsGenerate(gTts, text.c_str(), 0, 1.0f);
    if (audio == nullptr || audio->samples == nullptr || audio->n <= 0) {
        errOut = "SherpaOnnxOfflineTtsGenerate returned no audio";
        return false;
    }

    sampleRateOut = audio->sample_rate > 0 ? audio->sample_rate : 22050;
    pcmOut.resize(static_cast<size_t>(audio->n));
    for (int32_t i = 0; i < audio->n; ++i) {
        float v = audio->samples[i];
        if (v > 1.0f) {
            v = 1.0f;
        }
        if (v < -1.0f) {
            v = -1.0f;
        }
        pcmOut[static_cast<size_t>(i)] = static_cast<int16_t>(v * 32767.0f);
    }
    SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio);
    return true;
#endif
}
