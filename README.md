# Mencaje 翻译 · HarmonyOS 版

<p align="center">
  <strong>离线优先的多语言翻译应用</strong> · 基于 Meta NLLB-200 + CTranslate2 · 原生 Piper / SummerTTS 朗读
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-GPLv3-blue.svg" alt="License: GPL v3"/></a>
</p>

<p align="center">
  平台：<strong>HarmonyOS NEXT</strong>（手机 / 平板 / 2in1）<br/>
  包名：<code>com.Mencaje.translator</code><br/>
  仓库（主）：<a href="https://github.com/Mencaje/Mencaje.translatorHarmony">github.com/Mencaje/Mencaje.translatorHarmony</a><br/>
  镜像：<a href="https://gitee.com/mencaje/Mencaje.translatorHarmony">gitee.com/mencaje/Mencaje.translatorHarmony</a>（单文件 &gt;100MB 受限，大资源请用 GitHub + LFS）
</p>

---

## 目录

- [项目简介](#项目简介)
- [功能一览](#功能一览)
- [翻译：支持哪些语言](#翻译支持哪些语言)
- [朗读：支持哪些语言](#朗读支持哪些语言)
- [语言能力对照总表](#语言能力对照总表)
- [技术架构](#技术架构)
- [开源组件与许可证](#开源组件与许可证)
- [模型与数据许可说明](#模型与数据许可说明)
- [构建与运行](#构建与运行)
- [项目结构](#项目结构)
- [已知限制与路线图](#已知限制与路线图)
- [参与贡献](#参与贡献)
- [许可证](#许可证)

---

## 项目简介

**Mencaje 翻译（HarmonyOS）** 是萌创匠盒团队将 Android 版「Mencaje 翻译」移植到 **HarmonyOS NEXT** 的离线翻译应用。核心设计目标：

1. **完全离线翻译**：不依赖网络即可在设备上完成文本翻译（需预先安装约 2.3 GB 的 NLLB 模型包）。
2. **多语言覆盖**：基于 Meta **NLLB-200-distilled-600M**，在应用内暴露 **111 种** FLORES-200 语言，任意两种语言可互译（全连通，无方向限制）。
3. **本机朗读（TTS）**：中文走 **SummerTTS**，日语走 **piper-plus + OpenJTalk**，其余 **35+ 种语言** 走 **Piper ONNX** 神经语音模型。
4. **拍照翻译**：调用华为 **Core Vision Kit** OCR，识别后走同一套离线 NLLB 引擎。
5. **辅助功能**：闪控球（`USE_FLOAT_BALL` + `floatingBall` API，需 AGC ACL，见 `scripts/AGC_闪控球ACL申请.md`）。

本仓库为 **Stage 模型** 单模块应用（`entry`），含 **两套 Native NAPI**（翻译 + TTS）及完整构建脚本。

---

## 功能一览

| 功能 | 说明 | 是否需网络 |
|------|------|------------|
| 文本翻译 | 主页输入/粘贴，支持长文分块（≤280 字/块） | 否（需本地模型） |
| 双向语言栏 | 源语 / 目标语可互换，智能检测输入语种并自动决定翻译方向 | 否 |
| 双译模式 | 一次输入可同时译成语言栏上的两种语言 | 否 |
| 历史记录 | 本地持久化翻译历史 | 否 |
| 拍照翻译 | 相机取景 + OCR + 翻译 | 否（OCR 用系统能力） |
| 离线朗读 | 输入框 / 译文区扬声器按钮 | 否（需对应语音包） |
| 语音包管理 | 设置 → 朗读语言，按需安装各语种 ONNX / 词典 | 否（从 HAP 资源解压） |
| NLLB 模型包 | 小包 + 用户导入，或完整包内置 resfile | 首次导入可无网 |
| 开源协议页 | 应用内展示主要依赖及许可证链接 | — |
| 闪控球翻译 | 切到其他应用时显示闪控球，点击回应用 | 需 ACL Profile |

---

## 翻译：支持哪些语言

### 引擎与模型

| 项目 | 值 |
|------|-----|
| 模型 | [facebook/nllb-200-distilled-600M](https://huggingface.co/facebook/nllb-200-distilled-600M) |
| 运行时格式 | CTranslate2 INT8（`model.bin` + `shared_vocabulary.json` + SentencePiece） |
| 推理后端 | 自研 NAPI `libctranslate2_napi.so` → `libctranslate2.so` |
| 语言代码体系 | FLORES-200（如 `zho_Hans`、`eng_Latn`） |
| 语言对策略 | **全连通**：任意源语言 → 任意目标语言，无白名单矩阵 |
| 同语种 | 源 = 目标时原文直接返回 |

配置文件：`entry/src/main/resources/rawfile/flores200_languages.json`（由 `scripts/gen_flores_languages.js` 生成）。

### 111 种翻译语言（完整列表）

以下语言均在主页「原文 / 翻译成」语言选择器中出现，可任意两两互译：

| # | 中文名 | NLLB 代码 | ISO |
|---|--------|-----------|-----|
| 1 | 阿尔巴尼亚语 | als_Latn | als |
| 2 | 阿坎语 | aka_Latn | aka |
| 3 | 阿拉伯语 | arb_Arab | ar |
| 4 | 阿姆哈拉语 | amh_Ethi | amh |
| 5 | 阿萨姆语 | asm_Beng | asm |
| 6 | 阿塞拜疆语 | azj_Latn | azj |
| 7 | 阿斯图里亚斯语 | ast_Latn | ast |
| 8 | 阿瓦德语 | awa_Deva | awa |
| 9 | 埃及阿拉伯语 | arz_Arab | arz |
| 10 | 爱尔兰语 | gle_Latn | gle |
| 11 | 爱沙尼亚语 | est_Latn | est |
| 12 | 奥里亚语 | ory_Orya | ory |
| 13 | 巴什基尔语 | bak_Cyrl | bak |
| 14 | 巴斯克语 | eus_Latn | eus |
| 15 | 白俄罗斯语 | bel_Cyrl | bel |
| 16 | 班巴拉语 | bam_Latn | bam |
| 17 | 保加利亚语 | bul_Cyrl | bul |
| 18 | 北黎凡特阿拉伯语 | apc_Arab | apc |
| 19 | 冰岛语 | isl_Latn | isl |
| 20 | 波兰语 | pol_Latn | pl |
| 21 | 波斯尼亚语 | bos_Latn | bos |
| 22 | 波斯语 | pes_Arab | pes |
| 23 | 博杰普尔语 | bho_Deva | bho |
| 24 | 藏语 | bod_Tibt | bod |
| 25 | 丹麦语 | dan_Latn | dan |
| 26 | 德语 | deu_Latn | de |
| 27 | 俄语 | rus_Cyrl | ru |
| 28 | 法语 | fra_Latn | fr |
| 29 | 梵语 | san_Deva | san |
| 30 | 菲律宾语 | tgl_Latn | tgl |
| 31 | 芬兰语 | fin_Latn | fin |
| 32 | 高棉语 | khm_Khmr | khm |
| 33 | 格鲁吉亚语 | kat_Geor | kat |
| 34 | 古吉拉特语 | guj_Gujr | guj |
| 35 | 哈萨克语 | kaz_Cyrl | kaz |
| 36 | 韩语 | kor_Hang | ko |
| 37 | 豪萨语 | hau_Latn | hau |
| 38 | 荷兰语 | nld_Latn | nl |
| 39 | 吉尔吉斯语 | kir_Cyrl | kir |
| 40 | 加利西亚语 | glg_Latn | glg |
| 41 | 加泰罗尼亚语 | cat_Latn | cat |
| 42 | 捷克语 | ces_Latn | ces |
| 43 | 科萨语 | xho_Latn | xho |
| 44 | 克罗地亚语 | hrv_Latn | hrv |
| 45 | 拉脱维亚语 | lvs_Latn | lvs |
| 46 | 老挝语 | lao_Laoo | lao |
| 47 | 立陶宛语 | lit_Latn | lit |
| 48 | 卢森堡语 | ltz_Latn | ltz |
| 49 | 卢旺达语 | kin_Latn | kin |
| 50 | 罗马尼亚语 | ron_Latn | ron |
| 51 | 马达加斯加语 | plt_Latn | plt |
| 52 | 马拉地语 | mar_Deva | mar |
| 53 | 马拉雅拉姆语 | mal_Mlym | mal |
| 54 | 马来语 | zsm_Latn | zsm |
| 55 | 马其顿语 | mkd_Cyrl | mkd |
| 56 | 毛利语 | mri_Latn | mri |
| 57 | 美索不达米亚阿拉伯语 | acm_Arab | acm |
| 58 | 蒙古语 | khk_Cyrl | khk |
| 59 | 孟加拉语 | ben_Beng | ben |
| 60 | 缅甸语 | mya_Mymr | mya |
| 61 | 摩洛哥阿拉伯语 | ary_Arab | ary |
| 62 | 南非荷兰语 | afr_Latn | afr |
| 63 | 南黎凡特阿拉伯语 | ajp_Arab | ajp |
| 64 | 内志阿拉伯语 | ars_Arab | ars |
| 65 | 尼泊尔语 | npi_Deva | npi |
| 66 | 挪威语 | nob_Latn | nob |
| 67 | 旁遮普语 | pan_Guru | pan |
| 68 | 葡萄牙语 | por_Latn | pt |
| 69 | 齐切瓦语 | nya_Latn | nya |
| 70 | 日语 | jpn_Jpan | ja |
| 71 | 瑞典语 | swe_Latn | swe |
| 72 | 塞尔维亚语 | srp_Cyrl | srp |
| 73 | 僧伽罗语 | sin_Sinh | sin |
| 74 | 绍纳语 | sna_Latn | sna |
| 75 | 世界语 | epo_Latn | epo |
| 76 | 斯洛伐克语 | slk_Latn | slk |
| 77 | 斯洛文尼亚语 | slv_Latn | slv |
| 78 | 斯瓦希里语 | swh_Latn | swh |
| 79 | 宿务语 | ceb_Latn | ceb |
| 80 | 索马里语 | som_Latn | som |
| 81 | 塔吉克语 | tgk_Cyrl | tgk |
| 82 | 塔伊兹-亚丁阿拉伯语 | acq_Arab | acq |
| 83 | 泰卢固语 | tel_Telu | tel |
| 84 | 泰米尔语 | tam_Taml | tam |
| 85 | 泰语 | tha_Thai | th |
| 86 | 突尼斯阿拉伯语 | aeb_Arab | aeb |
| 87 | 土耳其语 | tur_Latn | tr |
| 88 | 威尔士语 | cym_Latn | cym |
| 89 | 沃洛夫语 | wol_Latn | wol |
| 90 | 乌尔都语 | urd_Arab | urd |
| 91 | 乌克兰语 | ukr_Cyrl | uk |
| 92 | 乌兹别克语 | uzn_Latn | uzn |
| 93 | 希伯来语 | heb_Hebr | heb |
| 94 | 希腊语 | ell_Grek | ell |
| 95 | 匈牙利语 | hun_Latn | hun |
| 96 | 巽他语 | sun_Latn | sun |
| 97 | 亚美尼亚语 | hye_Armn | hye |
| 98 | 亚齐语（阿拉伯文） | ace_Arab | ace |
| 99 | 伊博语 | ibo_Latn | ibo |
| 100 | 意大利语 | ita_Latn | it |
| 101 | 印地语 | hin_Deva | hi |
| 102 | 印尼语 | ind_Latn | id |
| 103 | 英语 | eng_Latn | en |
| 104 | 约鲁巴语 | yor_Latn | yor |
| 105 | 粤语 | yue_Hant | yue |
| 106 | 越南语 | vie_Latn | vi |
| 107 | 爪哇语 | jav_Latn | jav |
| 108 | 中部艾马拉语 | ayr_Latn | ayr |
| 109 | 中文（繁体） | zho_Hant | zh-Hant |
| 110 | 中文（简体） | zho_Hans | zh |
| 111 | 祖鲁语 | zul_Latn | zul |

### 翻译「不支持」或受限的情况

| 情况 | 说明 |
|------|------|
| NLLB 模型未安装 | 设置中导入 / 使用完整包；否则返回 `MODEL_NOT_READY` |
| 底层 NLLB-200 其余 ~89 种语言 | 模型词表支持约 200 语，UI 仅暴露 111 种 |
| **西班牙语 `spa_Latn`** | 在 `flores200_languages.json` 中**缺失**（生成脚本有映射但未写入 ENTRIES）；主页 JSON 加载后相机/首页 9 语中的 `es` 会失效 |
| 拍照目标语选择 | 仅 **9 种**「首页语言」：英/中/阿/日/韩/法/德/俄 + 理论上的西（西语因上条可能缺失） |
| OCR 语种标注 | 系统 OCR 自动检测，无手动语种参数；元数据标签主要覆盖 9 种 |
| 网络在线翻译 | `OnlineTranslateProvider`（MyMemory）已实现但**未接入**主流程 |

---

## 朗读：支持哪些语言

### 引擎分工

| 引擎 | 语种 | 模型 / 资源 |
|------|------|-------------|
| **SummerTTS** | 中文 `zh` | `single_speaker_fast.bin` |
| **piper-plus（日语专用）** | 日语 `ja` | `tsukuyomi-chan-6lang-fp16.onnx` + OpenJTalk 词典 |
| **Piper ONNX** | 见下表 34+3 种 | `rhasspy/piper-voices` 各语种 `.onnx` |
| **共享依赖** | 除 zh/ja 外 Piper 语种 | `espeak-ng-data`（音素化，GPL-3.0） |

目录源码：`entry/src/main/ets/tts/TtsVoiceCatalog.ets`、`TtsPiperVoiceCatalog.ets`。

### 支持朗读的 37 种语言

| ISO | 语言 | 引擎 | 声线 / 模型 |
|-----|------|------|-------------|
| zh | 中文 | SummerTTS | single_speaker_fast |
| ja | 日语 | piper-plus | tsukuyomi-chan-6lang |
| ru | 俄语 | Piper | ru_RU-denis-medium |
| en | 英语 | Piper | en_US-lessac-medium |
| uk | 乌克兰语 | Piper | uk_UA-ukrainian_tts-medium |
| pl | 波兰语 | Piper | pl_PL-darkman-medium |
| pt | 葡萄牙语 | Piper | pt_BR-faber-medium |
| ka | 格鲁吉亚语 | Piper | ka_GE-natia-medium |
| de | 德语 | Piper | de_DE-thorsten-medium |
| da | 丹麦语 | Piper | da_DK-talesyntese-medium |
| el | 希腊语 | Piper | el_GR-rapunzelina-low |
| fa | 波斯语 | Piper | fa_IR-ganji-medium |
| fi | 芬兰语 | Piper | fi_FI-harri-medium |
| cy | 威尔士语 | Piper | cy_GB-gwryw_gogleddol-medium |
| fr | 法语 | Piper | fr_FR-siwis-medium |
| hi | 印地语 | Piper | hi_IN-pratham-medium |
| hu | 匈牙利语 | Piper | hu_HU-anna-medium |
| is | 冰岛语 | Piper | is_IS-salka-medium |
| it | 意大利语 | Piper | it_IT-paola-medium |
| kk | 哈萨克语 | Piper | kk_KZ-issai-high |
| lb | 卢森堡语 | Piper | lb_LU-marylux-medium |
| lv | 拉脱维亚语 | Piper | lv_LV-aivars-medium |
| ml | 马拉雅拉姆语 | Piper | ml_IN-meera-medium |
| ne | 尼泊尔语 | Piper | ne_NP-google-medium |
| nl | 荷兰语 | Piper | nl_NL-pim-medium |
| no | 挪威语 | Piper | no_NO-talesyntese-medium |
| ro | 罗马尼亚语 | Piper | ro_RO-mihai-medium |
| sk | 斯洛伐克语 | Piper | sk_SK-lili-medium |
| sl | 斯洛文尼亚语 | Piper | sl_SI-artur-medium |
| sr | 塞尔维亚语 | Piper | sr_RS-serbski_institut-medium |
| sv | 瑞典语 | Piper | sv_SE-lisa-medium |
| sw | 斯瓦希里语 | Piper | sw_CD-lanfrica-medium |
| tr | 土耳其语 | Piper | tr_TR-dfki-medium |
| vi | 越南语 | Piper | vi_VN-vais1000-medium |
| ar | 阿拉伯语 | Piper 扩展 | ar_JO-kareem-medium |
| ca | 加泰罗尼亚语 | Piper 扩展 | ca_ES-upc_ona-medium |
| cs | 捷克语 | Piper 扩展 | cs_CZ-jirka-medium |

### 不支持朗读（重点列举）

**凡不在上表中的翻译语言，点击扬声器会提示「当前语言暂不支持朗读」。**

| 类别 | 语言示例 | 原因 |
|------|----------|------|
| 有翻译、无 TTS | **韩语 ko**、**泰语 th**、**印尼语 id**、**马来语**、**粤语 yue**、**繁体 zh-Hant**（未映射到 zh） | 未纳入 TTS 目录 |
| 有 Piper 资源但未开放 | **西班牙语 es** | 原生/脚本有 `es` 模型，UI 目录故意未收录 |
| 已移除 RHVoice | **吉尔吉斯 ky**、**马其顿 mk**、**阿尔巴尼亚 sq**、**世界语 eo** | 原 RHVoice/GPL-2.0 方案已下线 |
| 其余 ~74 种翻译语言 | 孟加拉、泰米尔、泰卢固、缅甸、希伯来、乌尔都… | 无对应语音包 |

语音包从 HAP `rawfile` / `resfile` 解压到 `filesDir/silero_tts/`，**运行时无需联网下载**。

---

## 语言能力对照总表

| 语言（中文） | 可翻译 | 可朗读 | 备注 |
|-------------|:------:|:------:|------|
| 中文（简体） | ✅ | ✅ SummerTTS | |
| 中文（繁体） | ✅ | ❌ | 可译；朗读未映射到 zh |
| 英语 | ✅ | ✅ Piper | |
| 日语 | ✅ | ✅ piper-plus | |
| 韩语 | ✅ | ❌ | |
| 俄语 | ✅ | ✅ Piper | |
| 法语 | ✅ | ✅ Piper | |
| 德语 | ✅ | ✅ Piper | |
| 西班牙语 | ⚠️ | ❌ | 翻译列表缺 spa_Latn（已知 bug） |
| 阿拉伯语 | ✅ | ✅ Piper 扩展 | |
| 葡萄牙语 | ✅ | ✅ Piper | |
| 乌克兰语 | ✅ | ✅ Piper | |
| 波兰语 | ✅ | ✅ Piper | |
| 格鲁吉亚语 | ✅ | ✅ Piper | |
| 越南语 | ✅ | ✅ Piper | |
| 泰语 | ✅ | ❌ | |
| 印尼语 | ✅ | ❌ | |
| 粤语 | ✅ | ❌ | |
| 世界语 | ✅ | ❌ | RHVoice 已移除 |
| 其余 90+ 语种 | ✅ | ❌ | 仅翻译 |

---

## 技术架构

```
┌──────────────────────────────────────────────────────────────┐
│  ArkTS UI（Index / CameraTranslate / TtsVoicePack / Settings）│
├────────────────────────────┬─────────────────────────────────┤
│  libctranslate2_napi.so    │  libsilero_tts_napi.so          │
│  CTranslate2 + SentencePiece│ SummerTTS + piper-plus + ORT   │
├────────────────────────────┴─────────────────────────────────┤
│  资源：NLLB CT2 模型 · Piper ONNX · espeak-ng-data · 中文 bin │
└──────────────────────────────────────────────────────────────┘
```

| 层级 | 路径 |
|------|------|
| 翻译入口 | `entry/src/main/ets/translation/OnDeviceTranslator.ets` |
| CT2 封装 | `entry/src/main/ets/translation/CTranslate2Engine.ets` |
| Native 桥 | `entry/src/main/cpp/ctranslate2_bridge.cpp` |
| TTS 引擎 | `entry/src/main/ets/tts/SileroTtsEngine.ets` |
| TTS 路由 | `entry/src/main/cpp/silero_tts_inference.cpp` |
| OCR | `entry/src/main/ets/translation/OcrHelper.ets` |

**SDK**：`compatibleSdkVersion` / `targetSdkVersion` = `5.0.2(14)`（API 14）  
**ABI**：`arm64-v8a`（真机）、`x86_64`（模拟器）

---

## 开源组件与许可证

### 运行时核心依赖

| 组件 | 版本（约） | 许可证 | 用途 |
|------|-----------|--------|------|
| [CTranslate2](https://github.com/OpenNMT/CTranslate2) | 4.7.x | **MIT** | NLLB 推理 |
| [SentencePiece](https://github.com/google/sentencepiece) | 0.2.0 | **Apache-2.0** | 分词 |
| [SummerTTS](https://github.com/huakunyang/SummerTTS) | — | **MIT** | 中文 TTS |
| [piper-plus](https://github.com/ayutaz/piper-plus) | 1.12.0 | **MIT** | 日语 + Piper 推理 |
| [ONNX Runtime](https://github.com/microsoft/onnxruntime) | 1.16.3 | **MIT** | ONNX 推理 |
| [Piper / piper-voices](https://huggingface.co/rhasspy/piper-voices) | v1.0.0 | **MIT**（模型权重） | 多语种声线 |
| [eSpeak-NG](https://github.com/espeak-ng/espeak-ng) | — | **GPL-3.0** | Piper 音素化（静态链接） |
| [OpenJTalk](https://github.com/r9y9/pyopenjtalk) 系 | 0.4.x | **Modified BSD** / MeCab 组件 | 日语 G2P |
| [Eigen](https://eigen.tuxfamily.org) | 3.4.0 | **MPL-2.0** | SummerTTS 线性代数 |
| [Ruy](https://github.com/google/ruy) | （CT2 内置） | **Apache-2.0** | CPU GEMM |
| [fmt](https://github.com/fmtlib/fmt) | 10.0.0 | **MIT** | piper-plus 格式化 |
| [spdlog](https://github.com/gabime/spdlog) | 1.12.0 | **MIT** | 日志 |

### 平台 SDK（非开源，需华为许可）

| 组件 | 用途 |
|------|------|
| HarmonyOS SDK / ArkUI / AbilityKit | 应用框架 |
| Core Vision Kit | 拍照 OCR |

### 仓库内已停用（保留源码，默认不编入 HAP）

| 组件 | 许可证 | 说明 |
|------|--------|------|
| RHVoice | **GPL-2.0+** | 已从 CMake 与目录移除 |
| Sherpa-ONNX | Apache-2.0 | 旧 TTS 路径，已关闭 |
| PyTorch Mobile | BSD-3-Clause | 旧 Silero JIT，已关闭 |

完整说明亦见应用内 **设置 → 开源协议**（`OpenSourceLicenseData.ets`）及仓库根目录 [`NOTICE`](NOTICE)。

---

## 模型与数据许可说明

| 资产 | 许可 | 注意 |
|------|------|------|
| **NLLB-200-distilled-600M** 权重 | **CC BY-NC 4.0**（Meta） | **禁止商业使用**（NonCommercial）；上架前须法务评估 |
| Piper 语音 ONNX | MIT（Rhasspy） | 各 `MODEL_CARD` 可能有额外条款 |
| SummerTTS 中文模型 | 随上游仓库 | 见 SummerTTS README |

---

## 构建与运行

### 环境要求

- DevEco Studio（HarmonyOS SDK **5.0.2(14)** 或兼容）
- OHOS Native SDK（Ninja + CMake ≥ 3.16）
- Windows：PowerShell 执行 `scripts/*.ps1`

### 首次构建（概要）

```powershell
# 1. 交叉编译 CTranslate2 + SentencePiece
.\scripts\build_ctranslate2_ohos.ps1
.\scripts\build_sentencepiece_ohos.ps1

# 2. 准备 TTS 原生库与语音资源
.\scripts\prepare_native_tts.ps1

# 3. 准备 NLLB 模型（体积大，见 scripts 下文档）
# 4. 配置签名：复制 build-profile.json5.example → build-profile.json5 并填入本机路径
# 5. DevEco Open Project → Run
```

详细步骤：

- 翻译原生库：`scripts/build_ctranslate2_ohos.md`
- TTS：`scripts/prepare_native_tts.ps1` 内注释
- 闪控球 ACL：`scripts/AGC_闪控球ACL申请.md`

### 签名配置

**切勿将含密码的 `build-profile.json5` 提交到公开仓库。** 使用 `build-profile.json5.example` 作模板。

---

## 项目结构

```
Mencajetranslator/
├── AppScope/                 # 应用级配置
├── entry/                    # 主模块
│   ├── src/main/ets/         # ArkTS 源码
│   │   ├── pages/            # 页面
│   │   ├── translation/      # 翻译引擎封装
│   │   ├── tts/              # 朗读引擎封装
│   │   └── floatball/        # 闪控球
│   ├── src/main/cpp/         # Native NAPI
│   ├── src/main/resources/   # 资源、rawfile 语言表
│   └── libs/<abi>/           # 预编译 .so（构建产物，常不入库）
├── CTranslate2/              # 翻译引擎源码（子模块式 vendoring）
├── third_party/              # sentencepiece、tts、onnxruntime 等
├── scripts/                  # 构建 / 打包 / ACL 文档
├── build-profile.json5.example
├── README.md
├── LICENSE
└── NOTICE
```

---

## 已知限制与路线图

- [ ] 修复西班牙语 `spa_Latn` 未写入 `flores200_languages.json`
- [ ] 韩语 TTS（`KoreanTTS-cpp` 占位）
- [ ] 可选开放西班牙语 Piper 朗读
- [ ] 鸿蒙 PC / 2in1：`SYSTEM_FLOAT_WINDOW` 悬浮窗（与手机闪控球分开）
- [ ] 繁体中文朗读映射到 `zh` SummerTTS

---

## 参与贡献

欢迎 Issue / PR。请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。

---

## 许可证

- **本仓库应用源码**（`entry/src/main/ets`、`entry/src/main/cpp` 中自研部分、`scripts` 等）：[**GNU General Public License v3.0**](LICENSE)（GPL-3.0）
- **第三方库**：各自许可证（MIT、Apache-2.0、GPL-3.0 等），见 [NOTICE](NOTICE)；与本项目组合分发时须遵守 GPL-3.0 对整体作品的约束
- **模型权重**：使用须遵守 Meta NLLB、Rhasspy Piper 等上游条款

---

<p align="center">萌创匠盒 · Mencaje Translator for HarmonyOS</p>
