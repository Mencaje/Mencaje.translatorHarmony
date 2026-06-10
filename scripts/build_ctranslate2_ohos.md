# 在 HarmonyOS 上启用完整 CTranslate2 + NLLB（免费、离线）

当前工程已包含：

- 源码：`CTranslate2/`（OpenNMT，MIT）
- NAPI 壳：`entry/src/main/cpp/` → `libctranslate2_napi.so`
- ArkTS：`CTranslate2Engine.ets` → 仅本机 NLLB 离线翻译（已移除 MyMemory 在线兜底）

**不需要向任何翻译 API 付费。**

## 1. 在 PC 上转换 NLLB 模型（一次性）

```bash
pip install ctranslate2 transformers sentencepiece
ct2-transformers-converter --model facebook/nllb-200-distilled-600M --output_dir nllb-200-distilled-600M
```

将生成的整个文件夹拷贝到手机应用私有目录（通过 hdc 或应用内下载）：

`files/models/nllb-200-distilled-600M/`

需含：`config.json`、`shared_vocabulary.json`、`sentencepiece.bpe.model`、`model.bin`（或分片索引）。

## 2. 交叉编译本机库（Windows + DevEco NDK）

在工程根目录 PowerShell 中（模拟器用 `x86_64`，真机用 `arm64-v8a`）：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build_ctranslate2_ohos.ps1 -Abi x86_64
powershell -ExecutionPolicy Bypass -File scripts\build_sentencepiece_ohos.ps1 -Abi x86_64
```

产物：`entry/libs/<abi>/libctranslate2.so` 与 `libsentencepiece.a`。  
`entry/src/main/cpp/ctranslate2_ohos.cmake` 会在编译 HAP 时自动链接并定义 `MENCAJE_CT2_LINKED=1`。

**必须启用 Ruy（`-DWITH_RUY=ON`）**，否则真机推理会报 `No SGEMM backend on CPU`。OHOS 使用 `cpuinfo` 的 `ohos_stubs.c`，无需完整 Linux `/proc` 解析。

NLLB 推理逻辑在 `ctranslate2_bridge.cpp`（SentencePiece + `translate_batch` + FLORES 语言码）。  
参考：<https://opennmt.net/CTranslate2/guides/transformers.html#nllb>

## 4. 验证

重新安装 HAP 后，日志应出现：

`CT2 init linked=true model=true`

此时中→乌等 200 语向均走本机 NLLB，不访问网络。
