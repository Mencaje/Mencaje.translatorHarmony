# 闪控球（USE_FLOAT_BALL）— 让应用能安装且悬浮球可用

## 当前卡在哪里？

| 检查项 | 你现在的状态 |
|--------|----------------|
| `module.json5` 声明 `USE_FLOAT_BALL` | 已写好（代码侧 OK） |
| 调试 Profile `.p7b` 的 `allowed-acls` | **仍是空的 `[]`** → 安装必报 **9568289** |

**结论：不是闪控球 API 写错了，是华为签名 Profile 还没带上 ACL。**  
在 ACL 开通并换好 `.p7b` 之前，工程里会**暂时去掉** `module.json5` 里的该权限，这样你能先正常 Run 其它翻译功能。

---

## 第一步：在 AGC 开通 ACL（必做，约 1 个工作日）

1. 打开 [AppGallery Connect](https://developer.huawei.com/consumer/cn/service/josp/agc/index.html)
2. 进入你的应用 → **用户与访问** → **证书、Profile 和密钥**
3. 若「受限权限」列表里**没有** `ohos.permission.USE_FLOAT_BALL`：
   - 发邮件到 **agconnect@huawei.com**
   - 主题示例：`申请 ACL 权限 USE_FLOAT_BALL`
   - 正文需包含：
     - **App ID**、包名 `com.Mencaje.translator`
     - 权限：`ohos.permission.USE_FLOAT_BALL`
     - 场景：辅助功能「悬浮窗翻译」，用户切到其它应用时显示**闪控球**，点击回到翻译 App
   - 等邮件批复（通常 1 个工作日内）
4. 批复后：**新建或编辑「调试」Profile**
   - 勾选受限权限：**ohos.permission.USE_FLOAT_BALL**
   - 绑定你的真机 **UDID**（调试 Profile 必须）
   - 下载新的 `.p7b`

5. 覆盖本地文件：

   ```
   D:\xiangmu\Mencaje.translatorHarmony\签名\调试\Mencaje.translator调试Debug.p7b
   ```

6. DevEco：**File → Project Structure → Signing Configs** → 重新选中该 p7b → Apply

7. 自检（PowerShell）：

   ```powershell
   powershell -ExecutionPolicy Bypass -File "d:\xiangmu\Mencaje.translatorHarmony\Mencajetranslator\scripts\check_profile_acl.ps1"
   ```

   必须看到：`USE_FLOAT_BALL: OK`

---

## 第二步：恢复工程里的权限声明并重装

ACL 的 Profile 就绪后，在 `entry/src/main/module.json5` 的 `requestPermissions` 中**重新加入**（见同目录 `module.json5.use_float_ball.snippet`），然后：

1. **Build → Clean Project**
2. 真机执行：`hdc shell bm uninstall -n com.Mencaje.translator`
3. **Run** 安装

此时不应再出现 9568289；安装后打开 **设置 → 辅助功能 → 悬浮窗翻译** 测试闪控球。

---

## 权限类型说明（官方 SDK）

`ohos.permission.USE_FLOAT_BALL`：

- **availableLevel**: `system_basic`（受限，必须 Profile ACL）
- **grantMode**: `system_grant`（安装时由 Profile 授予，不是普通弹窗权限）

因此：**没有 ACL 的 Profile = 不能安装；有 ACL 的 Profile = 安装后可直接调 `floatingBall` API。**

---

## 常见误区

| 误区 | 事实 |
|------|------|
| 用 `SYSTEM_FLOAT_WINDOW` 能在手机上当悬浮窗 | 仅 2in1/PC，手机请用 **闪控球 API** |
| 只改代码、不换 p7b | **无效**，9568289 是安装签名校验 |
| 用「发布 Profile」直接 Run 真机 | 应使用带设备 UDID 的**调试 Profile** |
