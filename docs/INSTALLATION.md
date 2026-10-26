# AIVoice2-Bridge 0.1.1 安装与使用

下载页：[Releases](https://github.com/CyanYuzu/AIVoice2-Bridge/releases)。
普通用户下载 **`AIVoice2-Bridge-0.1.1-win-x64.zip`**，不需要编译，也不要下载 GitHub 自动生成的 Source code 来安装。
0.1.0 包仍只适用于 2.13.0，不能用修改哈希表的方式让旧 DLL 支持新编辑器。

## 适用环境

- Windows x64，正版、已激活的 **A.I.VOICE2 Editor 2.13.0 或 2.14.1**，已安装并授权目标声库。
- 本版本核对原厂 EXE、Dart AOT、引擎及原插件属于同一份已验证构建；同版本名的其他文件组合也可能拒绝运行。2.14.0 不在验证范围内。
- 不支持一代 Editor，也不是一代 `TtsControl` 的 COM 兼容层。本地 API 为 JSON 命名管道协议 2。
- 安装到 Program Files 需要 Windows 管理员权限；日常打开 Editor 和使用调用方时保持同一 Windows 用户和权限级别。
- 用户不需要安装 Python、编译器或额外启动一个 API 服务。DLL 的直接依赖只有 Windows 系统 DLL。

## 下载内容

| 文件 | 用途 |
|---|---|
| `AIVoice2-Bridge-0.1.1-win-x64.zip` | 推荐，包含 DLL、安装/卸载脚本、说明、第三方许可与 DLL 校验值 |
| `window_size_plugin.dll` | 单独的桥接 DLL，供熟悉手工安装的用户使用 |
| `SHA256SUMS.txt` | Release 附件的 SHA-256 校验表 |

安装包不包含原厂 Editor、原插件、引擎、声库或许可文件。
下载后可用 `Get-FileHash .\AIVoice2-Bridge-0.1.1-win-x64.zip -Algorithm SHA256` 与校验表比较。
ZIP 若在 Windows 属性中显示“解除锁定”，先解除后再解压到一个可写目录。
包内 `editor-builds.json` 供安装检查使用，`COLLECT-DIAGNOSTICS.ps1` 供只读排障使用；两者都不需要复制进 Editor 根目录。

## 推荐安装

1. 保存项目，完全退出 A.I.VOICE2 Editor。
2. 解压 ZIP；不要直接在压缩包预览窗口里运行脚本。
3. 以管理员身份打开 PowerShell，进入解压目录，执行：

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\INSTALL.ps1
   ```

   自定义安装目录时：

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\INSTALL.ps1 -EditorRoot 'D:\Apps\AIVoice2Editor'
   ```

4. 脚本核对文件哈希，把原插件备份为 `aivoice2_window_size_original.dll`，再放入桥接 DLL。
   它只操作文件，不启动 Editor、不注册服务或自启动项。失败时查看当前解压目录的 `installation-result.json`。
5. 正常双击原版 `aivoice.exe`，等待声库和授权加载完成。之后 API 与 Editor 一起运行，关闭 Editor 后 API 也关闭。

原安装目录现在应同时保留这两个文件：

```text
AIVoice2Editor\
  aivoice.exe
  window_size_plugin.dll             ← 本 Release 的桥接 DLL
  aivoice2_window_size_original.dll   ← 用户自己原厂文件的完整备份，必须保留
```

## 手工复制安装

关闭 Editor，将原厂 `window_size_plugin.dll` **复制备份**为同目录的 `aivoice2_window_size_original.dll`，
然后把 Release 的 `window_size_plugin.dll` 覆盖到原目录。不要把一个已经替换过的桥接 DLL 当作原厂备份。
已验证原厂插件 SHA-256：`431767fa70d128427315b8b43a2be74a3da03a2d8a80679955522a917934ac4f`。
已有备份时不要覆盖它；推荐使用上面的脚本完成核对。

## 用于 YMM4

还需安装配套 [AIVoice2-Bridge YMM4 插件 v0.1.0](https://github.com/CyanYuzu/AIVoice2-Bridge-YMM4-plugin/releases/tag/v0.1.0)。
打开 Editor 后，在 YMM4 的 **A.I.VOICE2 Bridge** 设置页执行“检查连接”“更新声库”，
再在角色编辑器选择此引擎和实际声库，输入台词生成语音。完整步骤见插件的 Release 页面。
这个组合直接连接 Editor 内的 DLL，不需要 AIVoiceBridge HTTP 服务或 AstrBot 插件。

## 用于其他本地程序

发现文件为 `%LOCALAPPDATA%\AIVoice2Bridge\v2\editor-session.json`，包含当前 Editor PID 和管道名。
发现文件可能在退出后保留，存在文件本身不等于 Editor 正在运行，应查询 `health` 的 `ready`。

调用方以同一 Windows 用户连接 `\\.\pipe\AIVoice2Bridge2-<PID>`；每个连接写入一个 UTF-8 JSON 消息，
读回一个 JSON 回复后断开。不要使用 HTTP、COM 或一代的 `TtsControl` 调用方式。

```json
{"op":"health"}
{"op":"voices"}
{"op":"submit","request_id":"my_unique_job_001","text":"こんにちは。","voice":"YuzukiYukari_ns_48","parameters":{"rate":1.15,"pitch":1.0,"volume":0.9,"emphasis":1.0,"styles":{}}}
{"op":"status","id":"my_unique_job_001"}
```

上面是四个独立请求。`voice` 应取 `voices` 的实际 ID；`submit` 立即返回任务，轮询 `status`，
直到 `succeeded` 后读取 `result.output_path` 指向的 WAV。输出默认在本用户的 `v2\outputs` 中，
也可指定新的绝对 `.wav` 路径。每个任务使用新的 request_id；重试同一任务则保持 ID 和全部内容一致。
完整参数、取消和恢复协议见安装包 `API.md`，或仓库 [API 文档](https://github.com/CyanYuzu/AIVoice2-Bridge/blob/main/drop-in/README.md)。协议仍为 2，YMM4 配套插件 0.1.0 的请求格式不变。

## 卸载、恢复与升级

关闭 Editor，在解压目录用管理员 PowerShell 执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\INSTALL.ps1 -Uninstall
```

自定义目录时一并传入 `-EditorRoot`。也可手动把验证过的原厂备份复制回 `window_size_plugin.dll`。
卸载恢复原插件，不删除声库、项目或许可；如仍使用 YMM4 插件，应改选其他引擎或一并卸载该插件。
安装器只接受原厂插件、当前包或已知开发构建；遇到未知替换版会拒绝覆盖，先恢复原厂文件再安装。
升级原厂 Editor 前先卸载桥，升级后等待明确支持新版本的桥，不能跳过版本/哈希校验。

旧安装器卸载后可能保留 `aivoice2_window_size_original.dll`。升级 Editor 后若报 `INCOMPATIBLE_ORIGINAL_BACKUP`，不要把该旧备份恢复到新版目录。
先用官方安装器修复当前版本，确认 `window_size_plugin.dll` 已恢复为当前版本原厂文件，再将旧备份移到 Editor 目录之外保存，最后运行新版桥安装器。
安装与卸载都会拒绝跨版本备份，失败前不会改写 Editor 文件。

## 常见问题与验证范围

- **脚本提示拒绝访问**：关闭 Editor，并在管理员 PowerShell 中执行安装；不要改变 Program Files 的权限。
- **原插件备份缺失/哈希不匹配**：从合法安装恢复原厂文件，再重新安装本桥；Release 不提供原厂 DLL。
- **`EDITOR_UNAVAILABLE`**：正常打开已安装本桥的 Editor；使用同一用户，避免一个程序管理员运行、另一个普通运行。
- **`UNVERIFIED_EDITOR`**：原厂文件不属于本版本验证的构建，恢复原插件；不要强行绕过校验。
- **`UNVERIFIED_EDITOR_BUILD` / `Unknown editor plugin version`**：使用支持当前 Editor 的新安装包；错误日志会列出支持版本和实测哈希，不要只替换一个哈希或复用旧桥 DLL。
- **没有声库**：先在原版 Editor 中完成正版声库安装与授权，再查询/刷新声库。
- **能力范围**：支持文本合成、音量/语速/音高/抑扬/原生风格、WAV 和任务队列；不提供逐音素项目调谐、三档停顿或跨语种模型转换。

原 2.13.0 验收记录见 [docs/DROPIN-VALIDATION.md](https://github.com/CyanYuzu/AIVoice2-Bridge/blob/main/docs/DROPIN-VALIDATION.md)，2.14.1 及本次旧版回归见 [兼容性记录](https://github.com/CyanYuzu/AIVoice2-Bridge/blob/main/docs/COMPATIBILITY-2.14.1.md)。其他 Editor 构建、长期压力和听感质量未作保证。

排障时可在解压目录运行：

```powershell
.\COLLECT-DIAGNOSTICS.ps1 -EditorRoot 'C:\Program Files\AI\AIVoice2\AIVoice2Editor' -OutFile .\editor-diagnostics.json
```

脚本只读取关键文件版本和哈希，不包含声库、许可内容或激活信息。启动校验失败时管道可能尚未创建，同时查看 `%LOCALAPPDATA%\AIVoice2Bridge\v2\last-fault.json`。
