# 2.14.1 兼容性调查与修复

调查日期：2026-10-26。对应 [issue #1](https://github.com/CyanYuzu/AIVoice2-Bridge/issues/1)。
本次保持编辑器根目录单 DLL 和命名管道协议 2；没有新增运行器、客户端服务、注入器或许可补丁。

## 已确认的安装拒绝原因

0.1.0 的安装器只接受 2.13.0 原插件哈希，DLL 启动时还固定校验旧版 EXE、Dart AOT、引擎和原插件备份。
官方 2.14.1 安装包内的 `window_size_plugin.dll` 哈希与 issue 的报告一致：
`c36a58f89cea57deca1375065658444c70417f05abd1cfb2f5190f31b26db84b`。
四个关键文件都已变化，因此仅编辑旧安装器的一个哈希仍会在 DLL 启动时被拒绝。

来源为官方 [Editor 下载页](https://aivoice.jp/member/downloads/editor) 提供的
`https://aivoice.jp/member/storage/dl/editor/2.14.1/AIVoice2Editor.msi`。
MSI 的 AI,INC. Authenticode 签名验证有效；SHA-256：
`81a5d80ada94d6646373b9ab54dcfe4ddd824c45a66c7f071648a54838c92d90`。
用户提供的 [琴叶下载页](https://aivoice.jp/member/downloads/character/Kotonoha#aivoice2) 也可到达官方 2.14.1 下载入口。

完整的 2.13.0 和 2.14.1 指纹保存在 [configs/editor-builds.json](../configs/editor-builds.json)。
安装器按整组文件选择构建，DLL 使用由同一来源生成的内嵌配置；不会分别接受不同版本的单个文件。

## 接口比较结果

| 文件 / 边界 | 已观察到的事实 | 验证方法与范围 |
|---|---|---|
| `aivoice.exe` | 版本由 2.13.0 变为 2.14.1，仍导入 `WindowSizePluginRegisterWithRegistrar` | PE 导入及实际代理加载；未声称整个 EXE 不变 |
| `window_size_plugin.dll` | 导出入口保留；`WindowSizePluginRegisterWithRegistrar` 的 REA 反编译结果两版一致，仍建立 `flutter/windowsize` 通道并注册插件 | REA/Ghidra 12.1.4；新版原插件在编辑器中实际加载 |
| `data/app.so` | SHA-256 改变 | 固定为新版完整构建的一部分；未对整份 Dart AOT 进行等价性证明 |
| `Lib/AITalk/aitalk_engine.dll` | 文件版本 4.9.1.0 → 4.12.0.0；316 个旧导出保留，新增 `ai_TalkerConfig_setPauseCost`、`ai_TalkerConfig_setPauseFrequency` | 实际 PE 导出枚举；新函数的取值和行为未验证，未加入本次 API |
| `ai_Talker_talk` / `ai_Talker_loadDic` | 仍分别使用对象/文本/模式三参数、声库加载五参数边界 | REA 反编译及 x64 反汇编；许可检查继续由原厂引擎执行 |
| `ai_TalkerConfig_setRate` 等参数设置 | 桥实际使用的 27 个完整导出名均保留；归一化代码地址后的选定导出指令序列一致 | 保留寄存器、栈/对象偏移、常量和指令，仅归一化地址；不是整个引擎的等价性证明 |
| `ai_TtsCallbackSink_new` / `ai_Talker_setSink` | handler/user 二参数约定保持；sink 为引擎借用指针，释放前仍先 detach | REA 调用关系及回调 trampoline 反汇编 |
| BUFREQ / BUFDONE / marker | 事件 16 字节、payload 指针位于 +8；缓冲描述 32 字节，字段偏移 0/8/16/24；marker 步长 80 字节保持 | REA 与反汇编交叉核查，随后通过真实声库 WAV、取消及恢复测试验证 |

桥的合成链仍为：编辑器正常初始化引擎和授权 → 桥调用 `ai_Talker_new` →
`ai_Talker_loadLangDic` / `ai_Talker_loadDic` → `ai_Talker_selectVoiceDic` →
`ai_TalkerConfig_*` → `ai_Talker_setSink` → `ai_Talker_talk` → BUFREQ/BUFDONE 回调 → WAV 保存。
内部 Talker/config 对象始终由原厂函数创建和管理。

原插件注册证据 ID：旧 `ev_024b6219c1dc07e682b46ca41e0f422c4f6101874c0abffcc1c342148b35365f`，
新 `ev_808f9c0d1e44d87a7859e8ecb8fb9973c26c89318794088bb5d80327eec9c239`。
新版引擎核心证据：

- `ai_Talker_talk`：`ev_c7078d583cc69b9c70995fa653541614758aff01e7b25aa0b8d75089e63666f7`
- `ai_Talker_loadDic`：`ev_060fa5efb82a979c854ac670422d3f45b2c00257eaefe6cca11037acb089ab6b`
- BUFREQ：`ev_268f0ab9c47973bd1e0546109db6372306b4f46caf02165da1c80a415ced4906`
- BUFDONE：`ev_54f2aff335c10d00fd0dfea52cdcd6690afcf44376e3bc0acb665d6bf03de1f3`
- marker：`ev_c88ae4fce30d2300f3f0a5a6c9a116cae3827933f5a28b01af03dffceca270d5`

原始证据、反汇编、REA 快照及音频保留于本机 `evidence/compatibility-2.14.1/`，不分发原厂程序、声库或许可文件。

## 隔离运行方法与边界

使用 Sandboxie 独立的文件/注册表空间。先验证沙盒中写入的文件和注册表探针在宿主机均不可见，
并确认测试进程加载了 Sandboxie 模块。现有用户编辑器进程全程保留。

官方 MSI 的管理安装映像在沙盒内成功提取。正常升级尝试在 Sandboxie 中因旧版快捷方式 ACL/权限错误 1326 回滚，
因此本次运行验证采用完整管理安装映像覆盖沙盒中的虚拟 Program Files；没有宣称 MSI 常规升级流程在 Sandboxie 中通过。
使用的是未经修改的新版官方程序文件，声库和原厂许可流程沿用本机正常安装；未复制、编辑或绕过激活信息。
API 状态目录在沙盒内独立创建，不复用宿主机任务队列。

两版分别运行 `scripts/test-dropin.ps1` 与 `scripts/test-dropin-restart.ps1`。
测试支持指定 `ExpectedEditorPid`、`ExpectedBuildId`，重启只针对明确选择的测试进程；有未保存工程时拒绝关闭。
测试进程枚举使用 Windows Toolhelp，避免沙盒中 WMI 权限限制被误判为合成失败。
正常关闭通过保留的原生进程句柄检查实际退出码，不能只根据进程消失或 `.NET Process.ExitCode` 的空值作结论。
这些脚本仅供开发验证，不是桥运行依赖。

验收计数、最终 DLL 哈希和批处理测量见 [compatibility-validation.json](compatibility-validation.json)。

| 编辑器 | 真实合成 | 重启 / 关闭验收 |
|---|---|---|
| 2.14.1 | 8 声库，77/77 | 严格复测 14/14，保留进程句柄确认退出码 0；复测前等待 UI 完成启动 |
| 2.13.0 | 8 声库，77/77 | 早期行为检查 14/14；追加退出码检查的复测遇到 Flutter 异常，未完成，不计作严格正常关闭通过 |

批处理时间来自 Sandboxie 环境，不能与旧版无沙盒测试直接比较，也不代表长期压力测试或任意文本的性能保证。
没有新增听感质量、跨语种发音质量或未安装声库的验收结论。

额外的启动后快速关闭探针发现 `flutter_windows.dll + 0xc91491 / 0xc0000409`。
将 `window_size_plugin.dll` 恢复为原厂 2.14.1 文件、不加载桥接 DLL 的对照中，也观察到相同模块、偏移和异常码。
因此不能将它直接归因为桥接 ABI；具体原因仍未确认。该异常和快速关闭延迟单独记录，
不算作正常关闭通过，也不把 Sandboxie 的启动/关闭路径描述为无异常。
2.13.0 的追加关闭复测也出现同一 Flutter 模块异常；本次没有修改该原厂模块。

## 修复与升级方式

0.1.1 同时支持目录中两份已验证完整构建；保留现有 ABI 实现。
`abi_profile=aitalk-2.13.0-x64` 表示该 ABI 实现最初验证于 2.13.0，2.14.1 已通过相同边界的比较和运行验证，不表示检测成旧编辑器。
`health` 追加 `editor_build`、`editor_version`、`abi_profile`；协议仍为 2，调用方无需改请求格式。

安装、卸载和原插件转调都先校验完整组合；未知版本、新旧核心混装、跨版本备份均被拒绝。
安装错误包含支持版本和实测哈希；启动拒绝在管道创建之前写入 `last-fault.json`。
构建脚本记录目录及源码摘要，打包时拒绝目录已更新而 DLL 未重编的组合。

回归还重现了一项原有的启动竞态：外部状态查询以不共享删除的方式读取 `editor-session.json` 时，
一次性的 `MoveFileExW` 原子替换可返回错误 5，留下完整 `.tmp` 并终止 API 初始化。
旧实现用 1000ms 读锁可重现该问题。本次保留先写入、刷新临时文件再原子替换的方式，
仅对访问/共享/锁冲突限时 2 秒重试；不会先删除旧日志，也不会无限等待。
测试分别检查短锁后提交新完整 JSON 并恢复 ready，以及持续锁超过上限时保留旧完整 JSON、报告可诊断错误。

原厂 Editor 升级前先卸载桥。旧卸载器可能保留旧备份：若新版安装报 `INCOMPATIBLE_ORIGINAL_BACKUP`，
先用官方安装器恢复当前版本的原厂插件，再把旧备份移出 Editor 目录保存，然后安装 0.1.1。
绝不能把 2.13.0 备份恢复到 2.14.1 目录，或把新版原插件哈希塞进 `known_bridge_sha256` 来放行。

只读收集命令与完整安装步骤见 [INSTALLATION.md](INSTALLATION.md)。2.14.0 和其他未列入目录的构建仍不在支持范围内。
