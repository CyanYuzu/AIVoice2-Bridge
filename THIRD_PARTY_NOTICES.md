# 第三方工具与依赖

运行时不分发 A.I.VOICE2、声库或许可文件；它们必须由用户合法安装。

- [nlohmann/json](https://github.com/nlohmann/json/tree/v3.12.0)：MIT，仓库内 `tools/json.hpp` 自带版权声明，许可全文见 `drop-in/LICENSE.nlohmann-json.txt`。Bridge DLL 使用该库解析本地 JSON。
- [MinHook](https://github.com/TsudaKageyu/minhook/tree/v1.3.4)：BSD 2-Clause，仅分析探针使用，正式 Bridge 不链接它。
- [REA](https://github.com/morluto/rea)：固定 npm 包 6.5.0，本地研究工具，见随包许可。
- [Ghidra](https://github.com/NationalSecurityAgency/ghidra)：12.1.4，本地研究工具，见官方发布许可。
- Microsoft Sysinternals Handle、MSVC、现有 JDK、Python、ILSpy、pefile、Capstone 分别适用其原始许可；它们不是语音引擎实现的一部分。
