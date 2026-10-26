# 根目录 DLL 部署验收

本文保留 0.1.0 / Editor 2.13.0 的历史验收。0.1.1 的 2.14.1 适配、两版回归及当前支持范围见 [COMPATIBILITY-2.14.1.md](COMPATIBILITY-2.14.1.md)。

当前桥为 `drop-in/window_size_plugin.dll`，安装于原版
`C:\Program Files\AI\AIVoice2\AIVoice2Editor\window_size_plugin.dll`。
原插件保留为同目录 `aivoice2_window_size_original.dll`，SHA-256 为
`431767fa70d128427315b8b43a2be74a3da03a2d8a80679955522a917934ac4f`。
原 EXE、Dart AOT 和合成引擎文件固定哈希，启动时校验。

只正常启动原版编辑器，未使用 LoadLibrary 注入器、Python、启动器或服务。
编辑器加载替换插件后，由插件转调备份原插件；桥自己的线程等待原版完成引擎初始化，
再调用原厂接口创建独立 Talker。根目录 API DLL 本身不调用 CreateProcess、ShellExecute、
WinExec、CreateRemoteThread、VirtualAllocEx、WriteProcessMemory；PE 导入表保存在
`evidence/dropin-pe.txt`。仅凭导入表不能证明所有动态行为，源代码检查和运行时进程快照
共同确认桥不创建辅助进程。

`scripts/test-dropin.ps1` 是开发验证脚本，使用当前 PowerShell 会话的 .NET 管道 API
发送请求，没有新建或运行客户端应用、Python 进程或测试 EXE，不是部署依赖。
机器可读结果：`evidence/dropin-e2e.json`。

验证包括 8 个正版声库实际合成、WAV RIFF/48kHz/单声道/PCM16、文件 SHA-256、
同文同参逐字节一致、语速影响时长、音量/音高/抑扬/原生风格改变波形、参数隔离、
原厂参数错误与恢复、排队与运行中取消、部分文件清理、批处理串行执行与一致性、
请求幂等及冲突拒绝、实际加载模块、安装目录、无编辑器子进程和 API 所属进程。
性能值仅适用于本次指定文本和本机，不作为长期稳定性或任意并发性能保证。

`scripts/test-dropin-restart.ps1` 在真实运行与排队任务存在时正常关闭原编辑器，
重新启动同一个原版 EXE，检查 DLL 自动加载、历史任务、运行任务中断标记、
遗留部分文件清理、排队任务续行、显式恢复和重启前后波形一致性。
机器可读结果：`evidence/dropin-restart.json`。

当前通过结果保存在 evidence/dropin-e2e.json 和 evidence/dropin-restart.json。

本地验收构建 DLL SHA-256（不同构建不保证字节相同）：`5b1f8ce4af7881edfd9cc4756df18012a49213001e4cc45af2cd768ca578b8c4`，536,576 字节。
修复后的完整合成检查 **77/77 通过**；原编辑器正常重启检查 **14/14 通过**。
8 个排队任务累计 33.8293 秒音频，墙钟 7.4975 秒，RTF 0.2216。
这些是原编辑器中的原厂合成结果；测试请求由已有 PowerShell 检查会话发出。
本地模块、文件哈希、进程及就绪状态记录于 `evidence/dropin-final.json`。

支持边界：固定 2.13.0/x64 和本机 8 个已授权二代声库。未验证数天级连续运行、
其他编辑器版本、用户自定义外部声库、逐音素项目调谐或任意跨语种发音质量。
API 文本合成使用原厂 ai_Talker_talk，不宣称完整复现编辑器的项目调谐与预处理。
原厂引擎硬崩溃仍会影响承载它的编辑器；桥不会另起程序接管，也不会自动强杀重启编辑器。
