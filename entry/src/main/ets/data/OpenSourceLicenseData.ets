/** 开源协议卡片（字段与 Android activity_open_source_licenses 一致） */
export interface OpenSourceLicenseEntry {
  name: string;
  license: string;
  role: string;
  licenseUrl: string;
  repoUrl: string;
}

export class OpenSourceLicenseData {
  static getEntries(): OpenSourceLicenseEntry[] {
    const list: OpenSourceLicenseEntry[] = [
      {
        name: 'CTranslate2',
        license: 'MIT License',
        role: '负责本应用的文本翻译。',
        licenseUrl: 'https://github.com/OpenNMT/CTranslate2/blob/master/LICENSE',
        repoUrl: 'https://github.com/OpenNMT/CTranslate2',
      },
      {
        name: 'SummerTTS',
        license: 'MIT License',
        role: '负责本应用中文语言的朗读。',
        licenseUrl: 'https://github.com/huakunyang/SummerTTS/blob/main/README.md#license',
        repoUrl: 'https://github.com/huakunyang/SummerTTS',
      },
      {
        name: 'piper-plus',
        license: 'MIT License（上游自标）；启用 Piper/espeak 系语种时本工程还会静态链接 eSpeak-NG（GPL-3.0，见下说明）',
        role: '负责本应用朗读合成引擎：日语（OpenJTalk + ONNX）；俄语、英语、乌克兰语、波兰语、西班牙语、葡萄牙语、格鲁吉亚语及阿拉伯语、加泰罗尼亚语、捷克语、威尔士语、丹麦语等 Piper 扩展语种亦经此引擎推理 ONNX 模型。' +
          '注意：这些 Piper/espeak 系语种在 piper-plus 管线中依赖 eSpeak-NG 做音素化（GPL-3.0），并非 piper-plus 自述 MIT 即可忽略；商用或计划开源发布前须法务评估。',
        licenseUrl: 'https://github.com/ayutaz/piper-plus/blob/master/LICENSE.md',
        repoUrl: 'https://github.com/ayutaz/piper-plus',
      },
      {
        name: 'Piper / piper-voices（Rhasspy）',
        license: 'MIT License（语音模型权重；各语音 MODEL_CARD 可能另有说明，上架前请核对）',
        role: '提供 Piper 神经语音模型文件（.onnx），本身为 MIT 权重包，例如俄语 denis、英语 lessac、乌克兰语 ukrainian_tts、波兰语 darkman、西班牙语 davefx、巴西葡语 faber、格鲁吉亚语 natia，以及阿拉伯语 kareem、加泰罗尼亚语 upc_ona 等。' +
          '模型推理与音素化由 piper-plus 完成；若使用 espeak 系语种，运行时还需 espeak-ng-data 词典包（数据随 eSpeak-NG 分发，GPL-3.0）。',
        licenseUrl: 'https://huggingface.co/rhasspy/piper-voices/blob/main/LICENSE',
        repoUrl: 'https://huggingface.co/rhasspy/piper-voices',
      },
      {
        name: 'ONNX Runtime',
        license: 'MIT License',
        role: '为 piper-plus / Piper 语音模型提供本机 ONNX 神经网络推理运行时。',
        licenseUrl: 'https://github.com/microsoft/onnxruntime/blob/main/LICENSE',
        repoUrl: 'https://github.com/microsoft/onnxruntime',
      },
      {
        name: '华为 Core Vision Kit',
        license: '遵循华为 HarmonyOS SDK 及相关 API 许可协议。',
        role: '负责拍照翻译时的文字识别。',
        licenseUrl: 'https://developer.huawei.com/consumer/cn/doc/harmonyos-references/core-vision-textrecognition',
        repoUrl: 'https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/core-vision-kit',
      },
    ];
    return list;
  }
}
