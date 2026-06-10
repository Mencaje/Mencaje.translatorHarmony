/**
 * RHVoice (LGPL-2.1+) — 俄/乌/波/西/葡/格鲁吉亚/吉尔吉斯等离线朗读。
 * 语音数据目录：{modelRoot}/rhvoice/（与 ArkTS RhvoiceModelInstaller 一致）
 */

#include "silero_tts_rhvoice.h"

#include <sys/stat.h>

#include <mutex>
#include <string>
#include <vector>

#ifdef SILERO_USE_RHVOICE

#include "RHVoice.h"

namespace {

constexpr char kRhvoiceSubDir[] = "rhvoice";

std::mutex gEngineMutex;
RHVoice_tts_engine gEngine = nullptr;
std::string gLoadedDataRoot;
int gSampleRate = 24000;

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

std::string RhvoiceDataRoot(const std::string &modelRoot)
{
    return JoinPath(modelRoot, kRhvoiceSubDir);
}

bool PathIsFile(const std::string &path, int64_t minBytes)
{
    struct stat st {};
    if (stat(path.c_str(), &st) != 0) {
        return false;
    }
    return S_ISREG(st.st_mode) && st.st_size >= minBytes;
}

const char *LanguageDirForIso(const std::string &iso)
{
    if (iso == "ru") {
        return "Russian";
    }
    if (iso == "en") {
        return "English";
    }
    if (iso == "uk") {
        return "Ukrainian";
    }
    if (iso == "pl") {
        return "Polish";
    }
    if (iso == "es") {
        return "Spanish";
    }
    if (iso == "pt") {
        return "Brazilian-Portuguese";
    }
    if (iso == "ka") {
        return "Georgian";
    }
    if (iso == "ky") {
        return "Kyrgyz";
    }
    if (iso == "tt") {
        return "Tatar";
    }
    if (iso == "mk") {
        return "Macedonian";
    }
    if (iso == "sq") {
        return "Albanian";
    }
    if (iso == "eo") {
        return "Esperanto";
    }
    return nullptr;
}

bool LanguageDirReady(const std::string &dataRoot, const char *langDir)
{
    if (langDir == nullptr || langDir[0] == '\0') {
        return false;
    }
    const std::string langBase = JoinPath(JoinPath(dataRoot, "languages"), langDir);
    const std::string langInfo = JoinPath(langBase, "language.info");
    if (!PathIsFile(langInfo, 16)) {
        return false;
    }
    // data_only 语言（波/西等）：graph.txt
    const std::string graphTxt = JoinPath(langBase, "graph.txt");
    if (PathIsFile(graphTxt, 64)) {
        return true;
    }
    const std::string tokFst = JoinPath(langBase, "tok.fst");
    if (!PathIsFile(tokFst, 1000)) {
        return false;
    }
    // F123 巴西葡语等：tok.fst + g2p.fst（世界语 g2p.fst 约 200B，不能用 1KB 下限）
    const std::string g2pFst = JoinPath(langBase, "g2p.fst");
    if (PathIsFile(g2pFst, 64)) {
        return true;
    }
    // English 等：tok.fst + cmulex.fst（无 g2p.fst）
    const std::string cmulexFst = JoinPath(langBase, "cmulex.fst");
    return PathIsFile(cmulexFst, 1000);
}

bool VoiceProfileDirReady(const std::string &dataRoot, const char *profileDir)
{
    if (profileDir == nullptr || profileDir[0] == '\0') {
        return false;
    }
    const std::string voiceInfo = JoinPath(JoinPath(JoinPath(dataRoot, "voices"), profileDir), "voice.info");
    return PathIsFile(voiceInfo, 16);
}

/** voices/ 子目录名（与 zip 解压路径、TtsVoiceCatalog.rhvoiceProfile 一致） */
const char *VoiceDirForIso(const std::string &iso)
{
    if (iso == "ru") {
        return "aleksandr";
    }
    if (iso == "en") {
        return "bdl";
    }
    if (iso == "uk") {
        return "natalia";
    }
    if (iso == "pl") {
        return "natan";
    }
    if (iso == "es") {
        return "mateo";
    }
    if (iso == "pt") {
        return "Leticia-F123";
    }
    if (iso == "ka") {
        return "natia";
    }
    if (iso == "ky") {
        return "azamat";
    }
    if (iso == "tt") {
        return "talgat";
    }
    if (iso == "mk") {
        return "kiko";
    }
    if (iso == "sq") {
        return "hana";
    }
    if (iso == "eo") {
        return "spomenka";
    }
    return nullptr;
}

/** RHVoice synth voice_profile（须与 voice.info 的 name= 一致，可与目录名不同） */
const char *VoiceSpeakProfileForIso(const std::string &iso)
{
    if (iso == "ru") {
        return "aleksandr";
    }
    if (iso == "en") {
        return "Bdl";
    }
    if (iso == "uk") {
        return "natalia";
    }
    if (iso == "pl") {
        return "natan";
    }
    if (iso == "es") {
        return "mateo";
    }
    if (iso == "pt") {
        return u8"Let\u00EDcia-F123";
    }
    if (iso == "ka") {
        return "natia";
    }
    if (iso == "ky") {
        return "azamat";
    }
    if (iso == "tt") {
        return "talgat";
    }
    if (iso == "mk") {
        return "kiko";
    }
    if (iso == "sq") {
        return "hana";
    }
    if (iso == "eo") {
        return "Spomenka";
    }
    return nullptr;
}

const char *VoiceProfileForIso(const std::string &iso)
{
    return VoiceDirForIso(iso);
}

struct SynthContext {
    std::vector<int16_t> *pcm;
    int *rate;
};

int SetSampleRateCb(int sampleRate, void *userData)
{
    auto *ctx = static_cast<SynthContext *>(userData);
    if (ctx != nullptr && ctx->rate != nullptr) {
        *(ctx->rate) = sampleRate > 0 ? sampleRate : 24000;
    }
    gSampleRate = sampleRate > 0 ? sampleRate : 24000;
    return 1;
}

int PlaySpeechCb(const short *samples, unsigned int count, void *userData)
{
    auto *ctx = static_cast<SynthContext *>(userData);
    if (ctx == nullptr || ctx->pcm == nullptr || samples == nullptr || count == 0) {
        return 1;
    }
    const size_t old = ctx->pcm->size();
    ctx->pcm->resize(old + count);
    for (unsigned int i = 0; i < count; ++i) {
        (*ctx->pcm)[old + i] = samples[i];
    }
    return 1;
}

/** 调用方已持有 gEngineMutex */
bool EnsureEngineLocked(const std::string &dataRoot, std::string &errOut)
{
    if (dataRoot.empty()) {
        errOut = "RHVoice data path empty";
        return false;
    }
    if (gEngine != nullptr && gLoadedDataRoot == dataRoot) {
        return true;
    }
    if (gEngine != nullptr) {
        RHVoice_delete_tts_engine(gEngine);
        gEngine = nullptr;
        gLoadedDataRoot.clear();
    }

    RHVoice_callbacks cbs {};
    cbs.set_sample_rate = SetSampleRateCb;
    cbs.play_speech = PlaySpeechCb;

    RHVoice_init_params init {};
    init.data_path = dataRoot.c_str();
    init.config_path = dataRoot.c_str();
    init.callbacks = cbs;
    init.options = RHVoice_preload_voices;

    gEngine = RHVoice_new_tts_engine(&init);
    if (gEngine == nullptr) {
        errOut = "RHVoice_new_tts_engine failed — check rhvoice voice data under " + dataRoot;
        return false;
    }
    gLoadedDataRoot = dataRoot;
    return true;
}

void ReleaseRhvoiceEngineLocked()
{
    if (gEngine != nullptr) {
        RHVoice_delete_tts_engine(gEngine);
        gEngine = nullptr;
    }
    gLoadedDataRoot.clear();
}

} // namespace

void RhvoiceReleaseCachedEngine()
{
#ifdef SILERO_USE_RHVOICE
    ReleaseRhvoiceEngineLocked();
#endif
}

bool RhvoiceIsAvailable()
{
    return true;
}

bool RhvoiceIsLangSupported(const std::string &langIso)
{
    return VoiceProfileForIso(langIso) != nullptr;
}

bool RhvoiceIsModelPresent(const std::string &langIso, const std::string &modelRoot)
{
    if (!RhvoiceIsLangSupported(langIso)) {
        return false;
    }
    const std::string root = RhvoiceDataRoot(modelRoot);
    struct stat st {};
    const std::string voicesDir = JoinPath(root, "voices");
    if (stat(voicesDir.c_str(), &st) != 0 || !S_ISDIR(st.st_mode)) {
        return false;
    }
    if (!VoiceProfileDirReady(root, VoiceDirForIso(langIso))) {
        return false;
    }
    return LanguageDirReady(root, LanguageDirForIso(langIso));
}

bool RhvoiceSynthesize(const std::string &langIso,
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
    const char *profileDir = VoiceDirForIso(langIso);
    const char *speakProfile = VoiceSpeakProfileForIso(langIso);
    if (profileDir == nullptr || speakProfile == nullptr) {
        errOut = "RHVoice: unsupported language " + langIso;
        return false;
    }
    const std::string dataRoot = RhvoiceDataRoot(modelRoot);
    if (!RhvoiceIsModelPresent(langIso, modelRoot)) {
        errOut = std::string("RHVoice voice not installed: voices/") + profileDir +
                 "/ (run pack_rhvoice_voices.ps1, install in 朗读语言)";
        return false;
    }

    SynthContext ctx { &pcmOut, &sampleRateOut };
    RHVoice_synth_params sp {};
    sp.voice_profile = speakProfile;
    // RHVoice: absolute_* in [-1,1], 0 = voice default; 1 = max (was wrongly 1.0 → too fast).
    sp.absolute_rate = sp.absolute_pitch = sp.absolute_volume = 0.0;
    sp.relative_rate = sp.relative_pitch = sp.relative_volume = 1.0;
    if (langIso == "en") {
        sp.relative_rate = 0.82;
    }
    sp.punctuation_mode = RHVoice_punctuation_default;
    sp.capitals_mode = RHVoice_capitals_default;

    std::lock_guard<std::mutex> lock(gEngineMutex);
    if (!EnsureEngineLocked(dataRoot, errOut)) {
        return false;
    }
    RHVoice_message msg = RHVoice_new_message(gEngine, text.c_str(),
        static_cast<unsigned int>(text.size()), RHVoice_message_text, &sp, &ctx);
    if (msg == nullptr) {
        errOut = std::string("RHVoice_new_message failed (profile=") + speakProfile +
                 ", check languages/" + (LanguageDirForIso(langIso) ? LanguageDirForIso(langIso) : "?") +
                 " data)";
        return false;
    }
    const int rc = RHVoice_speak(msg);
    RHVoice_delete_message(msg);
    if (rc != 1 || pcmOut.empty()) {
        errOut = "RHVoice_speak failed or no audio";
        return false;
    }
    if (sampleRateOut <= 0) {
        sampleRateOut = gSampleRate > 0 ? gSampleRate : 24000;
    }
    return true;
}

#else

void RhvoiceReleaseCachedEngine()
{
}

bool RhvoiceIsAvailable()
{
    return false;
}

bool RhvoiceIsLangSupported(const std::string &)
{
    return false;
}

bool RhvoiceIsModelPresent(const std::string &, const std::string &)
{
    return false;
}

bool RhvoiceSynthesize(const std::string &langIso,
                       const std::string &text,
                       const std::string &modelRoot,
                       std::vector<int16_t> &pcmOut,
                       int &sampleRateOut,
                       std::string &errOut)
{
    (void)text;
    (void)modelRoot;
    pcmOut.clear();
    sampleRateOut = 0;
    errOut = "RHVoice not linked; place libRHVoice.so in entry/libs/<abi> and rebuild";
    (void)langIso;
    return false;
}

#endif
