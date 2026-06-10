#pragma once

#include <string>

/** 是否已链接 CTranslate2 本体（阶段 2 编译后为 true） */
bool Ct2BridgeIsLinked();

/** 模型目录是否包含 NLLB CT2 必需文件 */
bool Ct2BridgeIsModelPresent(const std::string &modelDir);

/** 加载模型到内存（SentencePiece + Translator），成功返回 true */
bool Ct2BridgeLoadModel(const std::string &modelDir, std::string &errOut);

/**
 * 使用 NLLB/FLORES 语言码翻译。失败返回空字符串，错误写入 errOut。
 */
std::string Ct2BridgeTranslate(const std::string &text,
                               const std::string &sourceNllb,
                               const std::string &targetNllb,
                               const std::string &modelDir,
                               std::string &errOut);

std::string Ct2BridgeBuildInfo();
