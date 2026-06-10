# piper-plus offline build deps

Place these files here (run from repo root):

```powershell
powershell -ExecutionPolicy Bypass -File scripts\vendor_piper_deps.ps1
```

- `fmt-10.0.0.zip` (~900 KB)
- `spdlog-1.12.0.zip` (~330 KB)

CMake uses them instead of downloading from GitHub during `assembleHap`.
