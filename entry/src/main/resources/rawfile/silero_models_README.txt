Offline TTS rawfile layout (no Silero NC / no Sherpa):

- summer_single_speaker_fast.bin  — Chinese (SummerTTS)
- (ja) resfile/piperplus_ja_voice.zip — Japanese (piper-plus), not in rawfile
- resfile/piper_<iso>_voice.zip   — Piper 语种（含 pl / pt / en / ru / uk / ka 等）
- resfile/espeakdata.zip          — Piper espeak 系语种共用音素词典

Prepare: scripts/prepare_native_tts.ps1
Slim HAP (drop legacy Sherpa/Silero): scripts/prune_legacy_tts_assets.ps1
RHVoice lib: scripts/build_rhvoice_ohos.md
