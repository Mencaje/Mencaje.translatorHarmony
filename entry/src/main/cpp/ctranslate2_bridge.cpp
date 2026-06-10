#include "ctranslate2_bridge.h"

#include <sys/stat.h>

#include <cstdint>
#include <fstream>
#include <memory>
#include <mutex>
#include <vector>

#if defined(MENCAJE_CT2_LINKED) && MENCAJE_CT2_LINKED
#include <strings/string_view.h>
#include <sentencepiece_processor.h>
#include <ctranslate2/translator.h>
#include <ctranslate2/models/sequence_to_sequence.h>
#endif

namespace {

bool FileExists(const std::string &path)
{
    struct stat st {};
    return stat(path.c_str(), &st) == 0 && S_ISREG(st.st_mode);
}

bool DirExists(const std::string &path)
{
    struct stat st {};
    return stat(path.c_str(), &st) == 0 && S_ISDIR(st.st_mode);
}

/** NLLB-200-distilled-600M CT2 int8 model.bin is ~2.3GB; reject placeholder or partial copies */
constexpr uint64_t kModelBinMinBytes = 2000ULL * 1024 * 1024;

bool ModelBinUsable(const std::string &modelDir)
{
    const std::string bin = modelDir + "/model.bin";
    if (FileExists(bin)) {
        struct stat st {};
        if (stat(bin.c_str(), &st) == 0 && S_ISREG(st.st_mode) &&
            static_cast<uint64_t>(st.st_size) >= kModelBinMinBytes) {
            return true;
        }
        return false;
    }
    return FileExists(modelDir + "/model.bin.index");
}

#if defined(MENCAJE_CT2_LINKED) && MENCAJE_CT2_LINKED

class Ct2NllbRuntime {
public:
    bool Ensure(const std::string &modelDir, std::string &errOut)
    {
        std::lock_guard<std::mutex> lock(mu_);
        if (translator_ && modelDir_ == modelDir) {
            return true;
        }
        translator_.reset();
        sp_.reset();
        vocabTokens_.clear();
        vocabViews_.clear();
        modelDir_.clear();

        if (!Ct2BridgeIsModelPresent(modelDir)) {
            errOut = "model not present";
            return false;
        }

        const std::string spPath = modelDir + "/sentencepiece.bpe.model";
        auto sp = std::make_unique<sentencepiece::SentencePieceProcessor>();
        const auto spStatus = sp->Load(spPath);
        if (!spStatus.ok()) {
            errOut = "SentencePiece load failed: " + spStatus.ToString();
            return false;
        }

        ctranslate2::ReplicaPoolConfig poolConfig;
        poolConfig.num_threads_per_replica = 1;

        const ctranslate2::ComputeType computeTypes[] = {
            ctranslate2::ComputeType::INT8,
            ctranslate2::ComputeType::DEFAULT,
            ctranslate2::ComputeType::FLOAT32,
        };
        std::unique_ptr<ctranslate2::Translator> translator;
        std::string loadErr;
        bool loaded = false;
        for (const auto computeType : computeTypes) {
            try {
                translator = std::make_unique<ctranslate2::Translator>(
                    modelDir,
                    ctranslate2::Device::CPU,
                    computeType,
                    std::vector<int>{0},
                    false,
                    poolConfig);
                loaded = true;
                break;
            } catch (const std::exception &ex) {
                loadErr = ex.what();
                translator.reset();
            }
        }
        if (!loaded) {
            errOut = loadErr.empty() ? "Translator load failed" : loadErr;
            return false;
        }

        try {
            const auto model = translator->get_first_replica().model();
            const auto *seq2seq =
                dynamic_cast<const ctranslate2::models::SequenceToSequenceModel *>(model.get());
            if (seq2seq == nullptr) {
                errOut = "not a sequence-to-sequence model";
                return false;
            }
            vocabTokens_.clear();
            vocabViews_.clear();
            const auto &vocabulary = seq2seq->get_source_vocabulary();
            vocabTokens_.reserve(vocabulary.size());
            vocabViews_.reserve(vocabulary.size());
            for (size_t i = 0; i < vocabulary.size(); ++i) {
                vocabTokens_.emplace_back(vocabulary.to_token(i));
            }
            for (const auto &tok : vocabTokens_) {
                vocabViews_.emplace_back(tok.data(), tok.size());
            }
            const auto vocabStatus = sp->SetVocabulary(vocabViews_);
            if (!vocabStatus.ok()) {
                errOut = "SentencePiece SetVocabulary failed: " + vocabStatus.ToString();
                return false;
            }

            translator_ = std::move(translator);
            sp_ = std::move(sp);
            modelDir_ = modelDir;
            return true;
        } catch (const std::exception &ex) {
            errOut = ex.what();
            return false;
        }
    }

    std::string Translate(const std::string &text,
                          const std::string &sourceNllb,
                          const std::string &targetNllb,
                          std::string &errOut)
    {
        std::lock_guard<std::mutex> lock(mu_);
        if (!translator_ || !sp_) {
            errOut = "translator not loaded";
            return "";
        }

        std::vector<std::string> sourceTokens;
        sp_->Encode(text, &sourceTokens);
        sourceTokens.push_back("</s>");
        sourceTokens.push_back(sourceNllb);

        const std::vector<std::vector<std::string>> batch{sourceTokens};
        const std::vector<std::vector<std::string>> targetPrefix{{targetNllb}};

        ctranslate2::TranslationOptions options;
        options.beam_size = 1;
        options.max_decoding_length = 512;
        options.repetition_penalty = 1.15f;
        options.no_repeat_ngram_size = 3;
        options.max_input_length = 512;
        options.return_scores = false;
        options.disable_unk = true;

        try {
            const auto results =
                translator_->translate_batch(batch, targetPrefix, options);
            if (results.empty() || results[0].hypotheses.empty() || results[0].hypotheses[0].empty()) {
                errOut = "empty translation";
                return "";
            }

            const auto &hypothesis = results[0].hypotheses[0];
            size_t start = 0;
            if (!hypothesis.empty() && hypothesis[0] == targetNllb) {
                start = 1;
            }
            std::vector<std::string> outTokens(hypothesis.begin() + static_cast<long>(start),
                                               hypothesis.end());
            std::string decoded;
            sp_->Decode(outTokens, &decoded);
            return decoded;
        } catch (const std::exception &ex) {
            errOut = ex.what();
            return "";
        }
    }

private:
    std::mutex mu_;
    std::string modelDir_;
    std::unique_ptr<ctranslate2::Translator> translator_;
    std::unique_ptr<sentencepiece::SentencePieceProcessor> sp_;
    std::vector<std::string> vocabTokens_;
    std::vector<absl::string_view> vocabViews_;
};

Ct2NllbRuntime &GlobalCt2Runtime()
{
    static Ct2NllbRuntime runtime;
    return runtime;
}

#endif // MENCAJE_CT2_LINKED

} // namespace

bool Ct2BridgeIsLinked()
{
#if defined(MENCAJE_CT2_LINKED) && MENCAJE_CT2_LINKED
    return true;
#else
    return false;
#endif
}

bool Ct2BridgeIsModelPresent(const std::string &modelDir)
{
    if (!DirExists(modelDir)) {
        return false;
    }
    const std::string config = modelDir + "/config.json";
    const std::string vocab = modelDir + "/shared_vocabulary.json";
    const std::string spm = modelDir + "/sentencepiece.bpe.model";
    if (!FileExists(config) || !FileExists(vocab) || !FileExists(spm)) {
        return false;
    }
    return ModelBinUsable(modelDir);
}

bool Ct2BridgeLoadModel(const std::string &modelDir, std::string &errOut)
{
    errOut.clear();
    if (!Ct2BridgeIsLinked()) {
        errOut = "CTranslate2 library not linked";
        return false;
    }
#if defined(MENCAJE_CT2_LINKED) && MENCAJE_CT2_LINKED
    return GlobalCt2Runtime().Ensure(modelDir, errOut);
#else
    errOut = "CTranslate2 library not linked";
    return false;
#endif
}

std::string Ct2BridgeBuildInfo()
{
#if defined(MENCAJE_CT2_ABI)
    const std::string abi = MENCAJE_CT2_ABI;
#else
    const std::string abi = "unknown";
#endif
    if (Ct2BridgeIsLinked()) {
        return "CTranslate2 linked (NLLB offline) abi=" + abi;
    }
    return "NAPI shell only abi=" + abi +
           "; run scripts/build_ctranslate2_ohos.ps1 -Abi arm64-v8a, then DevEco Clean+Rebuild+reinstall";
}

std::string Ct2BridgeTranslate(const std::string &text,
                               const std::string &sourceNllb,
                               const std::string &targetNllb,
                               const std::string &modelDir,
                               std::string &errOut)
{
    errOut.clear();
    if (text.empty()) {
        errOut = "empty text";
        return "";
    }
    if (!Ct2BridgeIsModelPresent(modelDir)) {
        errOut = "model not present";
        return "";
    }
    if (!Ct2BridgeIsLinked()) {
        errOut = "CTranslate2 library not linked";
        return "";
    }

#if defined(MENCAJE_CT2_LINKED) && MENCAJE_CT2_LINKED
    auto &runtime = GlobalCt2Runtime();
    if (!runtime.Ensure(modelDir, errOut)) {
        return "";
    }
    return runtime.Translate(text, sourceNllb, targetNllb, errOut);
#else
    (void)sourceNllb;
    (void)targetNllb;
    errOut = "CTranslate2 library not linked";
    return "";
#endif
}
