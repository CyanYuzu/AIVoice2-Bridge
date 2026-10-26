# AIVoice2-Bridge 0.1.1 预览版

支持已验证完整文件组合的 **A.I.VOICE2 Editor 2.13.0 和 2.14.1 / Windows x64**，解决 #1 报告的新版本安装拒绝。
2.14.1 原插件哈希与报告一致；经 REA 比较及真实声库测试，桥现有的引擎调用与 16/32/80 字节回调边界兼容。

普通用户下载 **AIVoice2-Bridge-0.1.1-win-x64.zip**，解压后在管理员 PowerShell 中运行：

```powershell
.\INSTALL.ps1 -EditorRoot 'C:\Program Files\AI\AIVoice2\AIVoice2Editor'
```

安装前关闭 Editor，安装后正常打开原来的 Editor。部署的功能组件仍只有根目录 `window_size_plugin.dll`，
API 与编辑器同进程运行，无需另启 Python、服务、启动器或客户端程序。
ZIP 中的 `editor-builds.json`、诊断脚本和文档不需要复制进 Editor 目录。
本地命名管道协议仍为 2，配套 YMM4 插件 0.1.0 和已有调用方的请求格式不变。

安装器与 DLL 共用完整构建指纹，拒绝未知版本、新旧文件混装和跨版本原插件备份。
`health` 追加实际编辑器版本与构建标识；新增只读诊断收集脚本和更明确的安装错误。
同时修复状态查询短暂占用会话日志时，原子替换失败导致 API 无法完成启动的竞态。

升级 Editor 后如果提示 `INCOMPATIBLE_ORIGINAL_BACKUP`，不要恢复旧版备份：
先用官方安装器修复当前 Editor，确认恢复当前版本的原厂插件，再把旧备份移出 Editor 目录保存，重新安装本包。
卸载桥使用同一脚本加 `-Uninstall`。安装包不含 Editor、原插件、引擎、声库或许可文件。

两版均以 8 个本机已授权声库通过 77 项真实合成检查；2.14.1 的严格正常重启恢复检查 14/14 通过，并确认退出码 0。详情与计数见
[兼容性记录](https://github.com/CyanYuzu/AIVoice2-Bridge/blob/v0.1.1/docs/COMPATIBILITY-2.14.1.md)。
测试采用 Sandboxie 隔离，未升级宿主机旧版；MSI 常规升级在 Sandboxie 中因快捷方式权限错误回滚，运行测试使用官方完整管理安装映像。
附加关闭探针观察到 Flutter 异常，同一异常也在未加载桥的原版对照中复现；2.13.0 的追加严格关闭复测未通过，单独记录而不计作正常关闭成功。Sandboxie 仅用于本次测试，不是运行依赖。
这不构成其他构建、数天连续运行或听感/跨语种质量保证。

完整步骤：[安装与使用](https://github.com/CyanYuzu/AIVoice2-Bridge/blob/v0.1.1/docs/INSTALLATION.md)。
文件校验：将下载附件的 SHA-256 与 `SHA256SUMS.txt` 比较。
