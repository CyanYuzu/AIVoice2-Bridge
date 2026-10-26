# A.I.VOICE2 Editor 根目录 DLL API Bridge

普通用户可在 [Releases](https://github.com/CyanYuzu/AIVoice2-Bridge/releases) 下载预编译安装包。2.14.1 需要 0.1.1；旧 0.1.0 安装包只支持 2.13.0。
首次安装、YMM4 配套使用、卸载和故障排查见 [完整使用说明](docs/INSTALLATION.md)。

当前方案只有一个功能 DLL：`drop-in/window_size_plugin.dll`。
它替换原程序根目录同名插件，并转调原插件的备份 `aivoice2_window_size_original.dll`。
正常打开原版 `aivoice.exe`，API 自动在该编辑器进程中可用。
无需启动器、注入器、Python 服务或任何客户端程序保持运行；本 DLL 不启动任何进程。

安装、卸载及完整协议见 [drop-in/README.md](drop-in/README.md)。
安装只涉及备份和替换 DLL；关闭原编辑器后可手工复制，或以管理员身份执行
`drop-in/INSTALL.ps1`。原厂 DLL 的完整备份必须保留在安装目录。

API 是仅本机同一用户可访问的命名管道 `\\.\pipe\AIVoice2Bridge2-<编辑器PID>`。
它提供声库枚举、原厂语音参数、WAV 合成、串行任务队列、状态查询、取消和恢复。
发现信息与任务日志位于 `%LOCALAPPDATA%\AIVoice2Bridge\v2`。

合成调用直接转接已逆向验证的原厂 `aitalk_engine.dll` 中的
`ai_Talker_*`、`ai_TalkerConfig_*` 及音频回调；启动初始化与许可验证由原版编辑器完成。
不重做合成引擎、不修改声库、不绕过激活。
当前源码支持 A.I.VOICE2 Editor **2.13.0、2.14.1 / Windows x64** 的已验证完整文件组合。
安装器与 DLL 共用 [构建目录](configs/editor-builds.json)，拒绝未知版本及新旧文件混装。
2.14.1 的接口比较、隔离验证方法和升级注意事项见 [兼容性记录](docs/COMPATIBILITY-2.14.1.md)。

## 从源码构建

需要 Windows x64、PowerShell 和 Visual Studio 的 C++ x64 构建工具。
仓库包含编译所需的 nlohmann/json 单头文件及其 MIT 许可；无需安装分析工具即可构建。

```powershell
.\scripts\build-dropin.ps1
# 关闭 Editor 后，在管理员 PowerShell 中安装刚构建的 DLL：
.\drop-in\INSTALL.ps1
```

DLL、打包产物和本机验收文件由构建/测试生成，不提交到源码仓库。
本地 `evidence/` 保存原始分析和运行记录，未对外上传；公开验收摘要见
[docs/validation-summary.json](docs/validation-summary.json)。仓库不分发原版程序、声库或许可文件。

配套 YMM4 插件：[AIVoice2-Bridge-YMM4-plugin](https://github.com/CyanYuzu/AIVoice2-Bridge-YMM4-plugin)。

分析证据见 [docs/FINDINGS.md](docs/FINDINGS.md)，本部署验证见
[docs/DROPIN-VALIDATION.md](docs/DROPIN-VALIDATION.md)。

源码：`src/dropin.cpp` 为 DLL 自动加载、原插件转调、API 与队列；
`src/bridge.cpp` 为原厂引擎接口适配。`scripts/build-dropin.ps1` 仅编译 DLL。
`scripts/test-dropin.ps1` 为开发验证脚本，通过当前 PowerShell 会话调用编辑器，
不创建客户端应用，也不是运行依赖。
