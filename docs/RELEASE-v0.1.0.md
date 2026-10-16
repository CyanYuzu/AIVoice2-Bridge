首个公开预览版。用户可以直接下载编译产物，无需构建源码。

## 下载什么

- **推荐：`AIVoice2-Bridge-0.1.0-win-x64.zip`**：DLL、安装/卸载脚本、使用说明、API 协议、校验值和第三方许可。
- `window_size_plugin.dll`：单独 DLL，供手工安装。
- `SHA256SUMS.txt`：附件校验表。GitHub 自动生成的 Source code 是源码，不是安装包。

## 环境

Windows x64，正版且已激活的 **A.I.VOICE2 Editor 2.13.0**，已安装授权声库。
本版本固定校验原厂文件哈希，其他构建尚未支持。不是一代 COM/TtsControl 兼容层。
桥运行于原版 Editor 内，不启动任何辅助进程，不需要 Python、HTTP 服务或编译器。

## 安装

1. 保存项目并退出 Editor；下载、解除 ZIP 锁定（如有）并解压。
2. 在解压目录打开**管理员 PowerShell**，执行：

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\INSTALL.ps1
   # 非默认安装目录：追加 -EditorRoot 'D:\Apps\AIVoice2Editor'
   ```

3. 脚本自动备份原插件为 `aivoice2_window_size_original.dll`，安装同目录的 `window_size_plugin.dll`。**保留原厂备份。**
4. 正常打开原版 Editor，等待声库和授权加载完成，API 即可使用。调用方与 Editor 应使用同一 Windows 用户和权限级别。

也可关闭 Editor 后手工备份原厂同名 DLL，再覆盖桥接 DLL；不要用桥接 DLL 覆盖原厂备份。

## 怎么使用

- **YMM4 用户**：再安装 [配套插件 v0.1.0](https://github.com/CyanYuzu/AIVoice2-Bridge-YMM4-plugin/releases/tag/v0.1.0)，在其设置页“检查连接”“更新声库”，选择引擎、声库并输入台词。
- **API 调用方**：从 `%LOCALAPPDATA%\AIVoice2Bridge\v2\editor-session.json` 获取 PID，连接同用户命名管道；使用 `health`、`voices`、`submit`、`status` 获取 WAV。完整消息示例和参数见包内 `API.md`。
- 本包提供声库枚举、原生参数、WAV、队列、状态、定向取消与空闲恢复；不包含原版程序、声库或许可，不提供逐音素编辑或未验证的跨语种功能。

## 卸载与升级

退出 Editor，在同一解压目录执行管理员命令：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\INSTALL.ps1 -Uninstall
```

自定义安装目录请同样追加 `-EditorRoot`。该操作恢复原厂插件。升级原厂 Editor 前先恢复原插件，新版本需等待适配。

当前真实验收覆盖 8 个正版声库、77 项合成检查与 14 项正常重启恢复检查；其他版本及数天持续运行未验证。
详细安装、故障排查和支持边界见[完整使用说明](https://github.com/CyanYuzu/AIVoice2-Bridge/blob/v0.1.0/docs/INSTALLATION.md)。
