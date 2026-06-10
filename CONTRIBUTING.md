# 参与贡献

感谢关注 Mencaje 翻译 HarmonyOS 版。

## 开发环境

- DevEco Studio + HarmonyOS SDK 5.0.2(14)
- 完成 `scripts/build_ctranslate2_ohos.ps1`、`scripts/prepare_native_tts.ps1` 等原生依赖准备
- 本地配置 `build-profile.json5`（勿提交含密码的文件）

## 提交流程

1. Fork 本仓库
2. 创建特性分支：`git checkout -b feature/your-topic`
3. 保持改动聚焦，匹配现有 ArkTS / CMake 风格
4. 若修改语言表：同步更新 `scripts/gen_flores_languages.js` 与 `flores200_languages.json`
5. 若新增 TTS 语种：同步 `TtsVoiceCatalog.ets`、native `piper_catalog`、`scripts/piper_voices_manifest.json`
6. 提交 PR 并说明测试设备与 HarmonyOS 版本

## 许可证

贡献代码默认以 [Apache-2.0](LICENSE) 授权，须确保不引入与项目策略冲突的 GPL 依赖（除非经讨论并更新 NOTICE）。
