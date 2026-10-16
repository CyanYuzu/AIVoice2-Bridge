# 仅 DLL 的编辑器内 API Bridge

适用：已验证哈希的 A.I.VOICE2 Editor 2.13.0，Windows x64。

安装时关闭原编辑器。在原程序根目录，将原 `window_size_plugin.dll` 备份为
`aivoice2_window_size_original.dll`，再将本目录的 `window_size_plugin.dll` 复制进去。
正常打开原来的 `aivoice.exe` 即会加载桥接 DLL。原插件注册功能由备份原 DLL 继续完成。
恢复时将备份复制回 `window_size_plugin.dll`。可选的 INSTALL.ps1 只执行这些文件操作，
不启动编辑器，不创建自启动项、服务或其他程序。Program Files 的复制需要管理员权限。

部署新增的功能组件只有一个 DLL。DLL 不调用 CreateProcess、ShellExecute、Python，
不需要启动器、注入器、独立服务器或客户端进程维持 API。
编辑器关闭，API 随之关闭。API 的监听线程、队列和合成工作线程全部属于原编辑器进程。

## 对外协议

本地命名管道：`\\.\pipe\AIVoice2Bridge2-<编辑器PID>`，仅允许本机同一用户访问。
发现文件：`%LOCALAPPDATA%\AIVoice2Bridge\v2\editor-session.json`。
每个连接发送一个 UTF-8 JSON 消息，读取一个 JSON 回复后断开；消息最大 60,000 字节。
成功为 `{"ok":true,"result":...}`，失败为 `{"ok":false,"error":...}`。
不附带、不运行 Python 客户端；任何未来调用方均可使用系统命名管道 API。

| op | 请求内容 | 功能 |
|---|---|---|
| health / ping | 仅 op | ready、pid、fault、队列数量 |
| voices | 仅 op | 正版声库 ID、名称、采样率、风格标签 |
| parameters | 仅 op | 原引擎参数边界、默认参数 |
| submit | request_id,text,voice,parameters,output_path,language | 提交合成，立即返回任务 |
| status | id | 查询任务与结果 |
| jobs | limit，1 至 100 | 最近任务；大回复需减小 limit |
| cancel | id | 取消排队或正在合成的任务 |
| recover | 仅 op | 空闲时重建桥接器自身 Talker |

示例请求只是协议说明，不会自动启动调用程序：

```json
{"op":"submit","request_id":"example-001","text":"こんにちは。","voice":"YuzukiYukari_ns_48","parameters":{"rate":1.15,"pitch":1.0,"volume":0.9,"emphasis":1.0,"styles":{"J":0.5}}}
```

`output_path` 可省略，默认输出到 `%LOCALAPPDATA%\AIVoice2Bridge\v2\outputs`；
指定时须为绝对 `.wav` 路径，不覆盖已有文件。`language` 默认为 standard，可用 kansai。
每个任务独立设置参数。状态有 queued、running、cancelling、succeeded、failed、cancelled、interrupted。
任务记录保存在 v2/jobs；编辑器异常退出后，原运行任务标记 interrupted，排队任务恢复。
相同 request_id 与相同内容返回同一个任务，不重复合成；不同内容拒绝复用。

调用链：本 DLL → 原厂 `ai_Talker_*` / `ai_TalkerConfig_*` → 原厂引擎 → 原厂音频回调 → WAV。
正常启动与授权由原编辑器完成。桥不调用原厂初始化/认证函数，不修改许可或声库。
使用独立 Talker，API 文本合成不宣称等同于编辑器的全部逐音素项目调谐。

当前验证范围详见工作区 docs/DROPIN-VALIDATION.md。
