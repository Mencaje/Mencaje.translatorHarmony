# RHVoice on HarmonyOS（LGPL-2.1+）

应用内 **俄语、乌克兰语、波兰语、西班牙语、葡萄牙语、格鲁吉亚语、吉尔吉斯语** 等由 RHVoice 朗读（见 `OpenSourceLicenseData.ets`）。

已 **剔除** Sherpa-ONNX / Silero（PyTorch）英法德西俄路径（NC 与体积原因）。

## 1. 源码

```powershell
powershell -ExecutionPolicy Bypass -File scripts\setup_rhvoice.ps1
```

## 2. 交叉编译 libRHVoice.so（Windows + DevEco NDK）

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build_rhvoice_ohos.ps1
# 模拟器可选：
powershell -File scripts\build_rhvoice_ohos.ps1 -Abi x86_64   # 模拟器 / x86 设备
```

产出：

- `entry/libs/arm64-v8a/libRHVoice.so`
- `entry/libs/x86_64/libRHVoice.so`（可选）

放入后 CMake 会定义 `SILERO_USE_RHVOICE` 并链接。若缺少 `cmake/thirdParty/sanitizers` 子模块，OHOS 构建会使用 `cmake/ohos_compat.cmake` 桩。

## 3. 语音数据（俄语优先）

**一键下载俄语声线 + 语言包并打入 HAP：**

```powershell
powershell -ExecutionPolicy Bypass -File scripts\setup_rhvoice_russian.ps1
```

产出 `entry/src/main/resources/rawfile/rhvoice_voices.zip`，内含：

- `voices/aleksandr/`（俄语默认男声）
- `languages/Russian/`（俄语分词/G2P 等，**必需**，否则引擎无法朗读）

然后 **Clean + Rebuild**，在 App「朗读语言」点 **俄语** 安装，翻译页选俄语后点朗读。

**英语（RHVoice · bdl）：**

```powershell
powershell -ExecutionPolicy Bypass -File scripts\setup_rhvoice_english.ps1
```

产出同一 `rhvoice_voices.zip`（追加 `voices/bdl/` + `languages/English/`）。若需俄英同时离线，先跑 `setup_rhvoice_russian.ps1` 再跑 `setup_rhvoice_english.ps1`（后者不删除已有俄语数据）。

**乌克兰语（RHVoice · natalia）：**

```powershell
powershell -ExecutionPolicy Bypass -File scripts\setup_rhvoice_ukrainian.ps1
```

追加 `voices/natalia/` + `languages/Ukrainian/`。多语并存时按需依次执行 ru / en / uk 脚本（各脚本只覆盖本语种目录，再统一 `pack_rhvoice_voices.ps1`）。

**格鲁吉亚语（RHVoice · natia）：**

```powershell
powershell -ExecutionPolicy Bypass -File scripts\setup_rhvoice_georgian.ps1
```

追加 `voices/natia/` + `languages/Georgian/`。

**吉尔吉斯语（RHVoice · azamat）：**

```powershell
powershell -ExecutionPolicy Bypass -File scripts\setup_rhvoice_kyrgyz.ps1
```

追加 `voices/azamat/` + `languages/Kyrgyz/`。

**鞑靼语（RHVoice · Talgat）：**

```powershell
powershell -ExecutionPolicy Bypass -File scripts\setup_rhvoice_tatar.ps1
```

追加 `voices/talgat/` + `languages/Tatar/`（勿与俄语女声 Tatiana 混淆）。

**马其顿语（RHVoice · Kiko）：**

```powershell
powershell -ExecutionPolicy Bypass -File scripts\setup_rhvoice_macedonian.ps1
```

追加 `voices/kiko/` + `languages/Macedonian/`。

**阿尔巴尼亚语（RHVoice · Hana）：**

```powershell
powershell -ExecutionPolicy Bypass -File scripts\setup_rhvoice_albanian.ps1
```

追加 `voices/hana/` + `languages/Albanian/`。

**世界语（RHVoice · Spomenka）：**

```powershell
powershell -ExecutionPolicy Bypass -File scripts\setup_rhvoice_esperanto.ps1
```

追加 `voices/spomenka/` + `languages/Esperanto/`。

手动方式：准备 `third_party/rhvoice/pack/voices/` 与 `pack/languages/`，再 `scripts\pack_rhvoice_voices.ps1`。

## 4. 与 piper-plus 共用 ONNX Runtime

日语 piper 仅需 `libonnxruntime.so`（**不再**依赖 Sherpa 的 libsherpa*.so）：

```powershell
powershell -File scripts\setup_onnxruntime_ohos.ps1
```

## 5. 一键准备

```powershell
powershell -File scripts\prepare_native_tts.ps1
```

HiLog `build=` 期望含 `[rhvoice]`，例如：

`TTS NAPI + SummerTTS(zh) + piper-plus(ja) + RHVoice(ru..ky) [summertts+piperplus+rhvoice]`
