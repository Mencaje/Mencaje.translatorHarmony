HarmonyOS 6 手机「翻译悬浮球」— 安装失败 9568289 处理说明
========================================================

现象
----
  Install Failed code:9568289
  grant request permissions failed
  PermissionName: ohos.permission.USE_FLOAT_BALL

原因
----
  USE_FLOAT_BALL 在 SDK 中为 availableLevel=system_basic（受限权限）。
  HAP 在 module.json5 里声明了该权限，但签名 Profile（.p7b）的
  acls.allowed-acls 里没有同名项时，安装阶段会直接失败。

  当前调试 Profile 实测（verify-profile）：
    D:/xiangmu/Mencaje.translatorHarmony/签名/调试/Mencaje.translator调试Debug.p7b
    → "allowed-acls": []   （空，故报错）

  发布 Profile 同样为空，上架前也需一并配置。

正确能力（手机）
----------------
  权限：ohos.permission.USE_FLOAT_BALL
  API：  @ohos.window.floatingBall（floatingBall.create / startFloatingBall）

  不要用 ohos.permission.SYSTEM_FLOAT_WINDOW + TYPE_FLOAT（仅 2in1/PC）。

必须操作：重新生成带 ACL 的 Profile（推荐 AGC）
----------------------------------------------
  1. 登录 AppGallery Connect → 用户与访问 → 证书、Profile 和密钥
  2. 为 com.Mencaje.translator 新建或编辑「调试」Profile
  3. 在「受限权限 / ACL」中勾选：
       ohos.permission.USE_FLOAT_BALL
     （若列表无此项，需先向华为申请 ACL，见下「邮件申请」）
  4. 下载新的 .p7b，覆盖：
       签名/调试/Mencaje.translator调试Debug.p7b
  5. DevEco：File → Project Structure → Project → Signing Configs
     重新选择上述 p7b，Apply → OK
  6. Build → Clean Project，再 Run
  7. 真机先卸载旧包：hdc shell bm uninstall -n com.Mencaje.translator
  8. 重新安装运行

  本地自检 Profile 是否已含 ACL（PowerShell）：

    $java = "D:\deveco studio\jbr\bin\java.exe"
    $jar  = "D:\deveco studio\sdk\default\openharmony\toolchains\lib\hap-sign-tool.jar"
    $out  = "$env:TEMP\profile-verify.json"
    & $java -jar $jar verify-profile `
      -inFile "D:/xiangmu/Mencaje.translatorHarmony/签名/调试/Mencaje.translator调试Debug.p7b" `
      -outFile $out
    Select-String -Path $out -Pattern "USE_FLOAT_BALL|allowed-acls"

  输出中 allowed-acls 应包含 ohos.permission.USE_FLOAT_BALL。

  也可运行项目脚本：
    scripts/check_profile_acl.ps1

邮件申请（AGC 里没有 USE_FLOAT_BALL 选项时）
--------------------------------------------
  收件：agconnect@huawei.com
  内容：App ID、包名 com.Mencaje.translator、申请 ohos.permission.USE_FLOAT_BALL、
        场景：辅助功能「悬浮窗翻译」闪控球，切到其他应用时快速回到翻译 App。
  批复后在 AGC 生成 Profile 时再勾选该受限权限。

参考 JSON 片段（仅供对照，实际须在 AGC 生成正式 p7b）
------------------------------------------------------
  见 scripts/harmony_debug_profile_float_acl.json

临时绕过（当前工程已启用，便于先 Run 其它功能）
----------------------------------------------
  已从 entry/src/main/module.json5 移除 USE_FLOAT_BALL。
  辅助功能里打开「悬浮窗翻译」会提示需先配置 AGC ACL。
  Profile 配好 ACL 后：把 module.json5.use_float_ball.snippet 内容
  加回 requestPermissions → 见 scripts/AGC_闪控球ACL申请.md

Profile 更新后的真机验证
------------------------
  1. 设置 → 辅助功能 → 打开「悬浮窗翻译」
  2. 按提示授权（若系统有闪控球相关开关）
  3. 切到其他应用，边缘出现闪控球；点击应回到本应用
