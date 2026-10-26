// Generated from configs/editor-builds.json. Run scripts/generate-build-profiles.ps1; do not edit.
#pragma once
#include <array>
namespace verified_builds {
struct Pin { const wchar_t* file; const char* sha256; };
struct Profile { const char* id; const char* editor_version; const char* abi_profile; std::array<Pin, 4> pins; };
inline constexpr std::array<Profile, 2> profiles{{
    Profile{"aivoice2-2.13.0-win-x64", "2.13.0", "aitalk-2.13.0-x64", {{
        Pin{L"aivoice.exe", "928e476e5038d6e1403d3f98fc5c644677473b627126d89055756c6b1b81f0c7"},
        Pin{L"data/app.so", "0c344cd779d788fa1cb45d0f833995c93fd5e687569c795824e600d6b59e56b9"},
        Pin{L"Lib/AITalk/aitalk_engine.dll", "b565b146b0b4de9cc07bacafbf680847f966d47fec733a6cf376b4089b381bf9"},
        Pin{L"aivoice2_window_size_original.dll", "431767fa70d128427315b8b43a2be74a3da03a2d8a80679955522a917934ac4f"},
    }}},
    Profile{"aivoice2-2.14.1-win-x64", "2.14.1", "aitalk-2.13.0-x64", {{
        Pin{L"aivoice.exe", "92f80c8ed10fb2c6a102541b82515a0bcd45b273b37b90e731f856786e797153"},
        Pin{L"data/app.so", "1cecf26ccecf3d6e89a6ae7a0962284fbe242cfffe3959f6a9eb052e432d5db6"},
        Pin{L"Lib/AITalk/aitalk_engine.dll", "711aa449c58754bd89402093e077695e8e6175159623c8cf063b979aa3515c17"},
        Pin{L"aivoice2_window_size_original.dll", "c36a58f89cea57deca1375065658444c70417f05abd1cfb2f5190f31b26db84b"},
    }}},
}};
} // namespace verified_builds
