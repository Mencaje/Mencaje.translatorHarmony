#include "silero_tts_bridge.h"
#include "silero_tts_inference.h"
#include "napi/native_api.h"

#include <mutex>
#include <string>
#include <vector>

namespace {

std::mutex gNativeAsyncMutex;

std::string GetStringArg(napi_env env, napi_value value)
{
    size_t len = 0;
    napi_get_value_string_utf8(env, value, nullptr, 0, &len);
    if (len == 0) {
        return "";
    }
    std::vector<char> buf(len + 1, '\0');
    size_t wrote = 0;
    napi_get_value_string_utf8(env, value, buf.data(), len + 1, &wrote);
    return std::string(buf.data(), wrote);
}

napi_value ToJsString(napi_env env, const std::string &s)
{
    napi_value out = nullptr;
    napi_create_string_utf8(env, s.c_str(), s.size(), &out);
    return out;
}

napi_value IsSileroLinked(napi_env env, napi_callback_info info)
{
    (void)info;
    napi_value result = nullptr;
    napi_get_boolean(env, SileroTtsIsLinked(), &result);
    return result;
}

napi_value IsLangModelPresent(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    const std::string root = argc > 0 ? GetStringArg(env, args[0]) : "";
    const std::string iso = argc > 1 ? GetStringArg(env, args[1]) : "";
    napi_value result = nullptr;
    napi_get_boolean(env, SileroTtsIsLangModelPresent(root, iso), &result);
    return result;
}

napi_value IsAnyModelPresent(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    const std::string root = argc > 0 ? GetStringArg(env, args[0]) : "";
    napi_value result = nullptr;
    napi_get_boolean(env, SileroTtsIsAnyModelPresent(root), &result);
    return result;
}

napi_value GetBuildInfo(napi_env env, napi_callback_info info)
{
    (void)info;
    return ToJsString(env, SileroTtsBuildInfo());
}

napi_value UsesSummerTts(napi_env env, napi_callback_info info)
{
    (void)info;
    napi_value result = nullptr;
    napi_get_boolean(env, SileroTtsUsesSummerTts(), &result);
    return result;
}

napi_value UsesPiperPlus(napi_env env, napi_callback_info info)
{
    (void)info;
    napi_value result = nullptr;
    napi_get_boolean(env, SileroTtsUsesPiperPlus(), &result);
    return result;
}

napi_value UsesRhvoice(napi_env env, napi_callback_info info)
{
    (void)info;
    napi_value result = nullptr;
    napi_get_boolean(env, SileroTtsUsesRhvoice(), &result);
    return result;
}

napi_value MakeSynthesizeResult(napi_env env,
                                bool ok,
                                const std::vector<int16_t> &pcm,
                                int sampleRate,
                                const std::string &err)
{
    napi_value obj = nullptr;
    napi_create_object(env, &obj);

    napi_value pcmVal = nullptr;
    if (ok && !pcm.empty()) {
        void *data = nullptr;
        napi_create_arraybuffer(env, pcm.size() * sizeof(int16_t), &data, &pcmVal);
        if (data != nullptr) {
            std::memcpy(data, pcm.data(), pcm.size() * sizeof(int16_t));
        }
    } else {
        napi_create_arraybuffer(env, 0, nullptr, &pcmVal);
    }
    napi_set_named_property(env, obj, "pcm", pcmVal);

    napi_value rateVal = nullptr;
    napi_create_int32(env, sampleRate, &rateVal);
    napi_set_named_property(env, obj, "sampleRate", rateVal);

    napi_set_named_property(env, obj, "error", ToJsString(env, err));

    napi_value okVal = nullptr;
    napi_get_boolean(env, ok, &okVal);
    napi_set_named_property(env, obj, "ok", okVal);

    return obj;
}

struct SynthesizeAsyncContext {
    napi_env env = nullptr;
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    uint64_t generationToken = 0;
    std::string langIso;
    std::string text;
    std::string modelRoot;
    std::vector<int16_t> pcm;
    int sampleRate = 0;
    std::string err;
    bool ok = false;
};

napi_value CancelSynthesis(napi_env env, napi_callback_info info)
{
    (void)info;
    SileroTtsCancelSynthesis();
    napi_value result = nullptr;
    napi_get_undefined(env, &result);
    return result;
}

void SynthesizeAsyncExecute(napi_env env, void *data)
{
    (void)env;
    std::lock_guard<std::mutex> nativeLock(gNativeAsyncMutex);
    auto *ctx = static_cast<SynthesizeAsyncContext *>(data);
    if (SileroInferenceIsCancelled(ctx->generationToken)) {
        ctx->ok = false;
        ctx->err = "synthesis cancelled";
        return;
    }
    ctx->ok = SileroTtsSynthesize(ctx->generationToken, ctx->langIso, ctx->text, ctx->modelRoot, ctx->pcm,
                                  ctx->sampleRate, ctx->err);
}

void SynthesizeAsyncComplete(napi_env env, napi_status status, void *data)
{
    auto *ctx = static_cast<SynthesizeAsyncContext *>(data);
    napi_value result = nullptr;
    if (status == napi_ok) {
        result = MakeSynthesizeResult(env, ctx->ok, ctx->pcm, ctx->sampleRate, ctx->err);
    } else {
        result = MakeSynthesizeResult(env, false, {}, 0, "async synthesize failed");
    }
    napi_resolve_deferred(env, ctx->deferred, result);
    napi_delete_async_work(env, ctx->work);
    delete ctx;
}

napi_value Synthesize(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value args[3] = {nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    napi_value promise = nullptr;
    napi_deferred deferred = nullptr;
    napi_create_promise(env, &deferred, &promise);

    auto *ctx = new SynthesizeAsyncContext();
    ctx->env = env;
    ctx->deferred = deferred;
    ctx->langIso = argc > 0 ? GetStringArg(env, args[0]) : "";
    ctx->text = argc > 1 ? GetStringArg(env, args[1]) : "";
    ctx->modelRoot = argc > 2 ? GetStringArg(env, args[2]) : "";
    ctx->generationToken = SileroInferenceCurrentGeneration();

    napi_value resourceName = nullptr;
    napi_create_string_utf8(env, "SileroSynthesize", NAPI_AUTO_LENGTH, &resourceName);
    napi_create_async_work(env, nullptr, resourceName, SynthesizeAsyncExecute, SynthesizeAsyncComplete, ctx,
                           &ctx->work);
    napi_queue_async_work(env, ctx->work);
    return promise;
}

napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        {"isSileroLinked", nullptr, IsSileroLinked, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"isLangModelPresent", nullptr, IsLangModelPresent, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"isAnyModelPresent", nullptr, IsAnyModelPresent, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getBuildInfo", nullptr, GetBuildInfo, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"usesSummerTts", nullptr, UsesSummerTts, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"usesPiperPlus", nullptr, UsesPiperPlus, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"usesRhvoice", nullptr, UsesRhvoice, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"synthesize", nullptr, Synthesize, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"cancelSynthesis", nullptr, CancelSynthesis, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}

} // namespace

extern "C" __attribute__((constructor)) void RegisterSileroTtsNapiModule(void)
{
    napi_module mod = {
        .nm_version = 1,
        .nm_flags = 0,
        .nm_filename = nullptr,
        .nm_register_func = Init,
        .nm_modname = "silero_tts_napi",
        .nm_priv = nullptr,
        .reserved = {0},
    };
    napi_module_register(&mod);
}
