# 鸿蒙离线朗读（TTS NAPI）

**不使用鸿蒙系统 TTS。** 本机 C++：`libsilero_tts_napi.so`。

## 架构

| 层 | 说明 |
|----|------|
| ArkTS | `SileroTtsEngine` → `SileroTtsNative` → `SileroPcmPlayer` |
| **中文 zh** | **SummerTTS**（MIT，`single_speaker_fast.bin`，16 kHz） |
| **日语 ja** | **piper-plus**（MIT，`tsukuyomi-chan-6lang-fp16.onnx` + OpenJTalk 词典，22.05 kHz） |
| **英 / 法 / 德 / 西 / 俄** | **Sherpa-ONNX + Piper**（`sherpa_*_vits.zip`） |
| 安装 | `SileroModelInstaller`：中文拷贝 `.bin`；其余解压 Sherpa zip |

### 中文语音包（必做）

```powershell
.\scripts\setup_tts_zh_ja_ko.ps1          # 克隆 SummerTTS（含 models/）
.\scripts\pack_summertts_zh_rawfile.ps1   # 打入 rawfile：summer_single_speaker_fast.bin (~76MB)
```

DevEco **Clean + Rebuild** 后，在「朗读语言」安装 **中文**；真机朗读测试 `zh`。

### 日语语音包

```powershell
.\scripts\pack_piperplus_ja_rawfile.ps1   # rawfile：piperplus_ja_voice.zip（ONNX+词典）
```

**Clean + Rebuild** 后在「朗读语言」安装 **日语**（`resfile/piperplus_ja_voice.zip`，约 57MB）。安装失败时 HiLog 过滤 `testTag`。若 HAP 安装报 `9568288 insufficient disk memory`，先运行 `scripts\prune_legacy_tts_assets.ps1` 删除已废弃的 Sherpa/Silero rawfile（约减 400MB），或给模拟器 **Wipe Data / 增大系统盘**，或 `build-profile.json5` 里临时只保留 `"x86_64"` 以去掉 arm64 库体积。**卸载旧应用再安装新 HAP**。启动 HiLog（`testTag`）应出现：

`TTS OK: Sherpa(en..ru) + SummerTTS(zh) + piper-plus(ja)` 且 `build=... [sherpa-v5+summertts+piperplus]`

若仍是 `[sherpa-v5+summertts]` 无 `piperplus`，说明装的是旧包或未用 arm64 真机编出的 HAP。

**Release 编 piper 报 `ohos.toolchain.cmake` / `CheckIPOSupported`：** 删除 `entry\.cxx\default\default\release` 后重编；工程已跳过 OHOS 上 LTO 检测并改用 `openharmony/native/build/cmake/ohos.toolchain.cmake` 给 ExternalProject。

### 模拟器 vs 真机（不必有实体手机才能测一部分）

| 运行环境 | CPU 切片 | 中文 zh | 英语 en 等 | 日语 ja |
|----------|----------|---------|------------|---------|
| DevEco **x86 模拟器** | `abi=x86_64` | SummerTTS ✓ | Sherpa ✓（需装语音包） | **未编入** piper-plus |
| **arm64 真机** 或 **arm64 模拟器** | `abi=arm64-v8a` | ✓ | ✓ | ✓（需装日语包 + HAP 含 `[piperplus]`） |

弹窗写「真机」是历史文案，实际限制是 **arm64 架构**，不是「必须有实体手机」。没有真机时：用模拟器先验证 **中文朗读**；日语需 DevEco 提供 **arm64 系统镜像** 的模拟器，或借一台鸿蒙手机装同一份 HAP。

若 `ProcessLibs` 报 `libpiper_plus.so` 重复或 **`libpiper_plus.so.1 does not exist`**：勿把 piper 放进 `entry/libs/`；运行 `scripts\clean_native_tts_build.ps1` 后 **Rebuild**（清除 hvigor 对旧 `.so.1` 的缓存；OHOS 仅产出 `libpiper_plus.so`）。

**英法德西俄：** `setup_sherpa_ohos.ps1 -PackEnVoice ...`（或 `prepare_native_tts.ps1`）。

## 模型文件（rawfile）

**推荐：在项目根目录 PowerShell 执行（需联网，约数百 MB）：**

```powershell
.\scripts\fetch_silero_rawfile_models.ps1
```

仅下载部分语种：`.\scripts\fetch_silero_rawfile_models.ps1 -Only en,de`

然后 DevEco **Rebuild** 并重新安装到手机；在「朗读语言」页点安装即可（不再报 rawfile 缺失）。

也可手动将下列文件放入 `entry/src/main/resources/rawfile/`，命名为：

| 语种 | silero-models 文件名 | rawfile 名 |
|------|---------------------|------------|
| en | `v3_en.pt` | `silero_v3_en.pt` |
| fr | `v3_fr.pt` | `silero_v3_fr.pt` |
| de | `v3_de.pt` | `silero_v3_de.pt` |
| es | `v3_es.pt` | `silero_v3_es.pt` |
| ru | `v5_cis_base_nostress.jit` | `silero_v5_cis_base_nostress.jit` |

可选整包：`silero_tts_models.zip`（后续可在安装器增加解压）。

## 阶段 2：链接推理库（当前状态）

| 步骤 | 状态 |
|------|------|
| 头文件 + `silero_v3_en_mobile.ptl` | 运行 `setup_pytorch_mobile.ps1`、`fetch_silero_rawfile_models.ps1` |
| ArkTS 安装/朗读校验（`.ptl` + `isSileroLibraryLinked()`） | 已实现 |
| C++ `silero_tts_inference.cpp`（PyTorch Mobile API） | 已实现 |
| **OHOS 可链接的 libtorch** | **未完成** |

**重要：** Maven 上的 `pytorch_android_lite` 仅含 **Android** 的 `libpytorch_jni_lite.so`（依赖 `libandroid.so` / Bionic `libc++_shared`），**不能**被 OpenHarmony 链接器链入 `libsilero_tts_napi.so`，也无法在真机加载。

### 路线 A：PyTorch Mobile（与当前 C++ 代码一致）

1. 用 DevEco/OpenHarmony NDK 交叉编译 PyTorch Mobile，产出 `entry/src/main/libs/arm64-v8a/libpytorch_ohos.so`（CMake 中链接名 `pytorch_ohos`）。
2. 头文件仍用 `scripts/setup_pytorch_mobile.ps1`（建议 PyTorch **2.1.x** 头文件与运行时版本一致）。
3. Rebuild HAP；设备上重新安装英语包（含 `v3_en_mobile.ptl`）。

### 路线 B：Sherpa-ONNX（当前默认，英语 Piper，Apache-2.0）

**一键准备（开发机 PowerShell）：**

```powershell
.\scripts\prepare_native_tts.ps1
```

等价于 `setup_sherpa_ohos.ps1 -PackEnVoice` + 校验 + 删除 `entry\.cxx`（避免 CMake 仍编出「未编入推理」的 stub）。

**真机 HiLog 必须出现：**

`Silero TTS linked=true build=Silero TTS NAPI + Sherpa-ONNX ... [sherpa-v1]`

若仍是 `linked=false` 且 build 含 `NO inference` / `setup_sherpa`，说明手机上的 HAP 仍是旧 native：DevEco **Build → Clean Project → Rebuild**，卸载应用后重装。

**推荐（无需自编译 libtorch）**：`.\scripts\setup_sherpa_ohos.ps1 -PackEnVoice` — 从官方 `sherpa_onnx.har` 提取 `libsherpa-onnx-c-api.so`、`libonnxruntime.so` 到 **`entry/libs/arm64-v8a/`**（该目录才会打进 HAP），并可选打包英语 Piper 语音到 rawfile。DevEco **Clean Project → Rebuild** 并重新安装后，在应用内安装英语语音包即可朗读。

**说明：** 法语/德/西/俄 rawfile 里的 Silero `.pt` 是「语音数据」；当前 Sherpa 构建**只支持英语朗读**。法语装完仍显示「待推理库」是因为本机 `libsilero_tts_napi.so` 未编入推理，与是否下载法语包无关。

1. `.\scripts\setup_onnxruntime_ohos.ps1` — 仅下载 `libonnxruntime.so`（若未跑 setup_sherpa 脚本）。
2. 将 Silero v3_en 导出为 ONNX，在 `silero_tts_inference` 或新文件中用 ORT C API 推理。
3. CMake 检测 `libonnxruntime.so` 后定义 `SILERO_USE_ONNXRUNTIME`。

桥接代码：`entry/src/main/cpp/silero_tts_bridge.{h,cpp}`、`silero_tts_inference.{h,cpp}`、`silero_napi_init.cpp`。

开源协议页已声明 **Silero Models**（CC BY-NC 4.0）负责英/法/德/西/俄朗读。
