/**
 * piper-plus (MIT) — 日语离线朗读，OpenJTalk + ONNX，通常 22050 Hz。
 */

#include "silero_tts_piperplus.h"

#ifdef SILERO_USE_PIPER_PLUS

#include "piper_plus.h"
#include "silero_tts_piper_catalog.h"

#include <sys/stat.h>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

namespace {

constexpr char kJaBundleDir[] = "piper-plus-ja";
constexpr char kPiperSubDir[] = "piper";
constexpr char kEspeakDataDir[] = "espeak-ng-data";
constexpr char kEspeakMarkerFile[] = "en_dict";
constexpr char kOnnxName[] = "tsukuyomi-chan-6lang-fp16.onnx";
constexpr char kConfigName[] = "config.json";
constexpr char kDictSubDir[] = "open_jtalk_dic";
constexpr int64_t kMinOnnxBytes = 8 * 1024 * 1024;
constexpr int64_t kMinDictMarkerBytes = 64 * 1024;

std::mutex gPiperMutex;
PiperPlusEngine *gEngine = nullptr;
std::string gLoadedBundleRoot;

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

std::string JaBundleRoot(const std::string &modelRoot)
{
    return JoinPath(modelRoot, kJaBundleDir);
}

std::string GenericBundleRoot(const std::string &modelRoot, const std::string &langIso)
{
    return JoinPath(JoinPath(modelRoot, kPiperSubDir), langIso);
}

std::string ConfigPathForOnnx(const std::string &onnxPath)
{
    return onnxPath + ".json";
}

bool FileLargeEnough(const std::string &path, int64_t minBytes)
{
    if (path.empty()) {
        return false;
    }
    struct stat st {};
    if (stat(path.c_str(), &st) != 0) {
        return false;
    }
    return S_ISREG(st.st_mode) && st.st_size >= minBytes;
}

std::string EspeakDataRoot(const std::string &modelRoot)
{
    return JoinPath(modelRoot, kEspeakDataDir);
}

bool EspeakDataReady(const std::string &modelRoot)
{
    return FileLargeEnough(JoinPath(EspeakDataRoot(modelRoot), kEspeakMarkerFile), 1024);
}

bool DirHasOpenJTalkDic(const std::string &dir)
{
    if (dir.empty()) {
        return false;
    }
    struct stat st {};
    const std::string sysDic = JoinPath(dir, "sys.dic");
    const std::string unkDic = JoinPath(dir, "unk.dic");
    return stat(sysDic.c_str(), &st) == 0 && S_ISREG(st.st_mode) && st.st_size > 1024 &&
           stat(unkDic.c_str(), &st) == 0 && S_ISREG(st.st_mode) && st.st_size > 1024;
}

std::string ResolveDictDir(const std::string &bundleRoot)
{
    const std::string direct = JoinPath(bundleRoot, kDictSubDir);
    if (DirHasOpenJTalkDic(direct)) {
        return direct;
    }
    const std::string alt = JoinPath(bundleRoot, "open_jtalk_dic_utf_8-1.11");
    if (DirHasOpenJTalkDic(alt)) {
        return alt;
    }
    if (DirHasOpenJTalkDic(bundleRoot)) {
        return bundleRoot;
    }
    return "";
}

void ReleaseEngine()
{
    if (gEngine != nullptr) {
        piper_plus_free(gEngine);
        gEngine = nullptr;
    }
    gLoadedBundleRoot.clear();
}

bool EnsureEngine(const std::string &bundleRoot,
                  const std::string &onnxName,
                  const std::string &configPath,
                  bool requireOpenJTalk,
                  const std::string &modelRoot,
                  std::string &errOut)
{
    if (gEngine != nullptr && gLoadedBundleRoot == bundleRoot) {
        return true;
    }
    ReleaseEngine();

    const std::string onnxPath = JoinPath(bundleRoot, onnxName);
    if (!FileLargeEnough(onnxPath, kMinOnnxBytes)) {
        errOut = "Piper ONNX model missing: " + onnxPath;
        return false;
    }
    if (!FileLargeEnough(configPath, 256)) {
        errOut = "Piper config missing: " + configPath;
        return false;
    }

    const char *dictDirCStr = nullptr;
    std::string dictDir;
    if (requireOpenJTalk) {
        dictDir = ResolveDictDir(bundleRoot);
        if (dictDir.empty()) {
            errOut = "OpenJTalk dictionary missing under " + bundleRoot;
            return false;
        }
        dictDirCStr = dictDir.c_str();
    }

    PiperPlusConfig cfg {};
    cfg.model_path = onnxPath.c_str();
    cfg.config_path = configPath.c_str();
    cfg.provider = "cpu";
    cfg.num_threads = 2;
    cfg.dict_dir = dictDirCStr;
    std::string espeakRoot = EspeakDataRoot(modelRoot);
    const char *espeakDirCStr = nullptr;
    if (!requireOpenJTalk && EspeakDataReady(modelRoot)) {
        espeakDirCStr = espeakRoot.c_str();
    }
    cfg.espeak_data_dir = espeakDirCStr;

    PiperPlusEngine *engine = nullptr;
    const PiperPlusStatus st = piper_plus_create(&cfg, &engine);
    if (st != PIPER_PLUS_OK || engine == nullptr) {
        const char *msg = piper_plus_get_last_error();
        errOut = msg != nullptr && msg[0] != '\0' ? std::string(msg) : "piper_plus_create failed";
        return false;
    }
    gEngine = engine;
    gLoadedBundleRoot = bundleRoot;
    return true;
}

bool EnsureJaEngine(const std::string &bundleRoot, std::string &errOut)
{
    // piper-plus-tsukuyomi 使用 config.json，非标准 Piper 的 *.onnx.json
    return EnsureEngine(bundleRoot, kOnnxName, JoinPath(bundleRoot, kConfigName), true, "", errOut);
}

int16_t FloatToPcm16(float sample)
{
    if (!std::isfinite(sample)) {
        return 0;
    }
    const float clamped = std::max(-1.0f, std::min(1.0f, sample));
    return static_cast<int16_t>(clamped * 32767.0f);
}

} // namespace

void PiperPlusReleaseCachedEngine()
{
#ifdef SILERO_USE_PIPER_PLUS
    std::lock_guard<std::mutex> lock(gPiperMutex);
    ReleaseEngine();
#endif
}

bool PiperPlusIsAvailable()
{
    return true;
}

bool PiperPlusIsJaModelPresent(const std::string &modelRoot)
{
    const std::string bundle = JaBundleRoot(modelRoot);
    if (!FileLargeEnough(JoinPath(bundle, kOnnxName), kMinOnnxBytes)) {
        return false;
    }
    if (!FileLargeEnough(JoinPath(bundle, kConfigName), 256)) {
        return false;
    }
    return !ResolveDictDir(bundle).empty();
}

bool PiperPlusSynthesizeJa(const std::string &text,
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
    const std::string bundle = JaBundleRoot(modelRoot);
    std::lock_guard<std::mutex> lock(gPiperMutex);
    if (!EnsureJaEngine(bundle, errOut)) {
        return false;
    }

    PiperPlusSynthOptions opts = piper_plus_default_options();
    int32_t langId = piper_plus_language_id(gEngine, "ja");
    if (langId < 0) {
        langId = 0;
    }
    opts.language_id = langId;

    float *samples = nullptr;
    int32_t numSamples = 0;
    int32_t sampleRate = 0;
    const PiperPlusStatus st =
        piper_plus_synthesize(gEngine, text.c_str(), &opts, &samples, &numSamples, &sampleRate);
    if (st != PIPER_PLUS_OK || samples == nullptr || numSamples <= 0) {
        const char *msg = piper_plus_get_last_error();
        errOut = msg != nullptr && msg[0] != '\0' ? std::string(msg) : "piper_plus_synthesize failed";
        if (samples != nullptr) {
            piper_plus_free_audio(samples);
        }
        return false;
    }

    pcmOut.resize(static_cast<size_t>(numSamples));
    for (int32_t i = 0; i < numSamples; ++i) {
        pcmOut[static_cast<size_t>(i)] = FloatToPcm16(samples[i]);
    }
    piper_plus_free_audio(samples);
    sampleRateOut = sampleRate > 0 ? sampleRate : 22050;
    return true;
}

bool PiperPlusIsGenericModelPresent(const std::string &langIso, const std::string &modelRoot)
{
    const PiperLangVoice *voice = PiperCatalogFind(langIso);
    if (voice == nullptr) {
        return false;
    }
    const std::string bundle = GenericBundleRoot(modelRoot, langIso);
    const std::string onnxPath = JoinPath(bundle, voice->onnxFile);
    const std::string configPath = ConfigPathForOnnx(onnxPath);
    return FileLargeEnough(onnxPath, kMinOnnxBytes) && FileLargeEnough(configPath, 256) &&
           EspeakDataReady(modelRoot);
}

bool PiperPlusSynthesizeGeneric(const std::string &langIso,
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
    const PiperLangVoice *voice = PiperCatalogFind(langIso);
    if (voice == nullptr) {
        errOut = "unsupported Piper language: " + langIso;
        return false;
    }
    const std::string bundle = GenericBundleRoot(modelRoot, langIso);
    if (!EspeakDataReady(modelRoot)) {
        errOut = "espeak-ng-data missing under " + modelRoot;
        return false;
    }
    const std::string onnxPath = JoinPath(bundle, voice->onnxFile);
    const std::string configPath = ConfigPathForOnnx(onnxPath);
    std::lock_guard<std::mutex> lock(gPiperMutex);
    if (!EnsureEngine(bundle, voice->onnxFile, configPath, false, modelRoot, errOut)) {
        return false;
    }

    PiperPlusSynthOptions opts = piper_plus_default_options();
    opts.language_id = -1;

    float *samples = nullptr;
    int32_t numSamples = 0;
    int32_t sampleRate = 0;
    const PiperPlusStatus st =
        piper_plus_synthesize(gEngine, text.c_str(), &opts, &samples, &numSamples, &sampleRate);
    if (st != PIPER_PLUS_OK || samples == nullptr || numSamples <= 0) {
        const char *msg = piper_plus_get_last_error();
        errOut = msg != nullptr && msg[0] != '\0' ? std::string(msg) : "piper_plus_synthesize failed";
        if (samples != nullptr) {
            piper_plus_free_audio(samples);
        }
        return false;
    }

    pcmOut.resize(static_cast<size_t>(numSamples));
    for (int32_t i = 0; i < numSamples; ++i) {
        pcmOut[static_cast<size_t>(i)] = FloatToPcm16(samples[i]);
    }
    piper_plus_free_audio(samples);
    sampleRateOut = sampleRate > 0 ? sampleRate : 22050;
    return true;
}

#else

void PiperPlusReleaseCachedEngine()
{
}

bool PiperPlusIsAvailable()
{
    return false;
}

bool PiperPlusIsJaModelPresent(const std::string &)
{
    return false;
}

bool PiperPlusIsGenericModelPresent(const std::string &, const std::string &)
{
    return false;
}

bool PiperPlusSynthesizeJa(const std::string &,
                           const std::string &,
                           std::vector<int16_t> &pcmOut,
                           int &sampleRateOut,
                           std::string &errOut)
{
    pcmOut.clear();
    sampleRateOut = 0;
    errOut = "piper-plus not compiled into libsilero_tts_napi";
    return false;
}

bool PiperPlusSynthesizeGeneric(const std::string &,
                                const std::string &,
                                const std::string &,
                                std::vector<int16_t> &pcmOut,
                                int &sampleRateOut,
                                std::string &errOut)
{
    pcmOut.clear();
    sampleRateOut = 0;
    errOut = "piper-plus not compiled into libsilero_tts_napi";
    return false;
}

#endif
