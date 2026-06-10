#include "ctranslate2_bridge.h"
#include "napi/native_api.h"

#include <memory>
#include <string>
#include <vector>

namespace {

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

napi_value MakeTranslateResult(napi_env env, const std::string &text, const std::string &err)
{
    napi_value obj = nullptr;
    napi_create_object(env, &obj);
    napi_set_named_property(env, obj, "text", ToJsString(env, text));
    napi_set_named_property(env, obj, "error", ToJsString(env, err));
    return obj;
}

napi_value IsCt2Linked(napi_env env, napi_callback_info info)
{
    (void)info;
    napi_value result = nullptr;
    napi_get_boolean(env, Ct2BridgeIsLinked(), &result);
    return result;
}

napi_value IsModelPresent(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    const std::string dir = argc > 0 ? GetStringArg(env, args[0]) : "";
    napi_value result = nullptr;
    napi_get_boolean(env, Ct2BridgeIsModelPresent(dir), &result);
    return result;
}

napi_value GetBuildInfo(napi_env env, napi_callback_info info)
{
    (void)info;
    return ToJsString(env, Ct2BridgeBuildInfo());
}

napi_value MakeLoadModelResult(napi_env env, bool ok, const std::string &err)
{
    napi_value obj = nullptr;
    napi_create_object(env, &obj);
    napi_value okVal = nullptr;
    napi_get_boolean(env, ok, &okVal);
    napi_set_named_property(env, obj, "ok", okVal);
    napi_set_named_property(env, obj, "error", ToJsString(env, err));
    return obj;
}

struct LoadModelAsyncContext {
    napi_env env = nullptr;
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    std::string modelDir;
    bool ok = false;
    std::string err;
};

void LoadModelAsyncExecute(napi_env env, void *data)
{
    (void)env;
    auto *ctx = static_cast<LoadModelAsyncContext *>(data);
    ctx->ok = Ct2BridgeLoadModel(ctx->modelDir, ctx->err);
}

void LoadModelAsyncComplete(napi_env env, napi_status status, void *data)
{
    auto *ctx = static_cast<LoadModelAsyncContext *>(data);
    napi_value result = nullptr;
    if (status == napi_ok) {
        result = MakeLoadModelResult(env, ctx->ok, ctx->err);
    } else {
        result = MakeLoadModelResult(env, false, "async loadModel failed");
    }
    napi_resolve_deferred(env, ctx->deferred, result);
    napi_delete_async_work(env, ctx->work);
    delete ctx;
}

napi_value LoadModel(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    napi_value promise = nullptr;
    napi_deferred deferred = nullptr;
    napi_create_promise(env, &deferred, &promise);

    auto *ctx = new LoadModelAsyncContext();
    ctx->env = env;
    ctx->deferred = deferred;
    ctx->modelDir = argc > 0 ? GetStringArg(env, args[0]) : "";

    napi_value resourceName = nullptr;
    napi_create_string_utf8(env, "CT2LoadModel", NAPI_AUTO_LENGTH, &resourceName);
    napi_create_async_work(env, nullptr, resourceName, LoadModelAsyncExecute, LoadModelAsyncComplete, ctx,
                           &ctx->work);
    napi_queue_async_work(env, ctx->work);
    return promise;
}

struct TranslateAsyncContext {
    napi_env env = nullptr;
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    std::string text;
    std::string src;
    std::string tgt;
    std::string modelDir;
    std::string outText;
    std::string err;
};

void TranslateAsyncExecute(napi_env env, void *data)
{
    (void)env;
    auto *ctx = static_cast<TranslateAsyncContext *>(data);
    ctx->outText = Ct2BridgeTranslate(ctx->text, ctx->src, ctx->tgt, ctx->modelDir, ctx->err);
}

void TranslateAsyncComplete(napi_env env, napi_status status, void *data)
{
    auto *ctx = static_cast<TranslateAsyncContext *>(data);
    napi_value result = nullptr;
    if (status == napi_ok) {
        result = MakeTranslateResult(env, ctx->outText, ctx->err);
    } else {
        result = MakeTranslateResult(env, "", "async translate failed");
    }
    napi_resolve_deferred(env, ctx->deferred, result);
    napi_delete_async_work(env, ctx->work);
    delete ctx;
}

napi_value Translate(napi_env env, napi_callback_info info)
{
    size_t argc = 4;
    napi_value args[4] = {nullptr, nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    napi_value promise = nullptr;
    napi_deferred deferred = nullptr;
    napi_create_promise(env, &deferred, &promise);

    auto *ctx = new TranslateAsyncContext();
    ctx->env = env;
    ctx->deferred = deferred;
    ctx->text = argc > 0 ? GetStringArg(env, args[0]) : "";
    ctx->src = argc > 1 ? GetStringArg(env, args[1]) : "";
    ctx->tgt = argc > 2 ? GetStringArg(env, args[2]) : "";
    ctx->modelDir = argc > 3 ? GetStringArg(env, args[3]) : "";

    napi_value resourceName = nullptr;
    napi_create_string_utf8(env, "CT2Translate", NAPI_AUTO_LENGTH, &resourceName);
    napi_create_async_work(env, nullptr, resourceName, TranslateAsyncExecute, TranslateAsyncComplete, ctx,
                           &ctx->work);
    napi_queue_async_work(env, ctx->work);
    return promise;
}

napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        {"isCt2Linked", nullptr, IsCt2Linked, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"isModelPresent", nullptr, IsModelPresent, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getBuildInfo", nullptr, GetBuildInfo, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"loadModel", nullptr, LoadModel, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"translate", nullptr, Translate, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}

} // namespace

extern "C" __attribute__((constructor)) void RegisterCtranlate2NapiModule(void)
{
    napi_module mod = {
        .nm_version = 1,
        .nm_flags = 0,
        .nm_filename = nullptr,
        .nm_register_func = Init,
        .nm_modname = "ctranslate2_napi",
        .nm_priv = nullptr,
        .reserved = {0},
    };
    napi_module_register(&mod);
}
