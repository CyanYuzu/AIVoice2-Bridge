// Loaded by the original editor's existing plugin import. No launcher or child process.
#include "bridge.cpp"
#include <bcrypt.h>
#include <condition_variable>
#include <deque>
#include <map>
#include <thread>

static std::mutex jobsMutex;
static std::condition_variable jobsChanged;
static std::map<std::string,json> jobs;
static std::deque<std::string> pending;
static fs::path stateRoot;
static std::atomic<bool> ready{false};
static json hostFault=nullptr,voiceCache=json::array(),limitCache=json::object();
static HMODULE selfModule;
static HANDLE stateLock=INVALID_HANDLE_VALUE;
static double timestamp(){return std::chrono::duration<double>(std::chrono::system_clock::now().time_since_epoch()).count();}
static json errorInfo(const Fault& e){return {{"code",e.code},{"stage",e.stage},{"native_code",e.native},{"message",e.what()}};}
static std::string sha256(const fs::path& path){
 BCRYPT_ALG_HANDLE alg=nullptr;BCRYPT_HASH_HANDLE hash=nullptr;
 if(BCryptOpenAlgorithmProvider(&alg,BCRYPT_SHA256_ALGORITHM,nullptr,0)<0)throw std::runtime_error("SHA256 provider unavailable");
 try{
  if(BCryptCreateHash(alg,&hash,nullptr,0,nullptr,0,0)<0)throw std::runtime_error("SHA256 initialization failed");
  std::ifstream f(path,std::ios::binary);if(!f)throw std::runtime_error("Cannot read integrity target");
  std::array<unsigned char,65536> block{};
  while(f){f.read((char*)block.data(),block.size());auto n=f.gcount();if(n&&BCryptHashData(hash,block.data(),(ULONG)n,0)<0)throw std::runtime_error("SHA256 update failed");}
  if(!f.eof())throw std::runtime_error("Integrity read failed");
  unsigned char digest[32];if(BCryptFinishHash(hash,digest,32,0)<0)throw std::runtime_error("SHA256 finalize failed");
  std::string result;const char* digits="0123456789abcdef";for(auto b:digest){result+=digits[b>>4];result+=digits[b&15];}
  BCryptDestroyHash(hash);BCryptCloseAlgorithmProvider(alg,0);return result;
 }catch(...){if(hash)BCryptDestroyHash(hash);BCryptCloseAlgorithmProvider(alg,0);throw;}
}
static void journal(const fs::path& path,const json& value){
 auto tmp=path;tmp+=L".tmp";auto data=value.dump(-1,' ',false,json::error_handler_t::replace);
 HANDLE f=CreateFileW(tmp.c_str(),GENERIC_WRITE,0,nullptr,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,nullptr);
 if(f==INVALID_HANDLE_VALUE)throw Fault("STATE_IO_ERROR","journal",GetLastError(),"Cannot write task journal");
 DWORD written=0;bool ok=WriteFile(f,data.data(),(DWORD)data.size(),&written,nullptr)&&written==data.size()&&FlushFileBuffers(f);CloseHandle(f);
 if(!ok||!MoveFileExW(tmp.c_str(),path.c_str(),MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH))throw Fault("STATE_IO_ERROR","journal",GetLastError(),"Cannot commit task journal");
}
static void saveJob(const json& j){journal(stateRoot/"jobs"/(j.at("id").get<std::string>()+".json"),j);}
static bool terminal(const std::string& s){return s=="succeeded"||s=="failed"||s=="cancelled"||s=="interrupted";}
static json health(){
 std::lock_guard<std::mutex> lock(jobsMutex);
 return {{"pid",GetCurrentProcessId()},{"protocol",2},{"deployment","editor-drop-in-dll"},{"backend","original-engine-in-editor"},{"ready",ready.load()},{"busy",busy.load()},{"fault",hostFault},{"queued",pending.size()},{"child_processes_started",0}};
}
static json route(const json& r){
 auto op=r.at("op").get<std::string>();
 if(op=="ping"||op=="health")return health();
 std::unique_lock<std::mutex> lock(jobsMutex);
 if(op=="status"){
  auto id=r.at("id").get<std::string>();if(!jobs.count(id))throw Fault("JOB_NOT_FOUND",op,0,"Unknown task ID");return jobs.at(id);
 }
 if(op=="jobs"){
  int count=r.value("limit",20);if(count<1||count>100)throw Fault("INVALID_REQUEST",op,0,"limit must be 1..100");
  std::vector<json> ordered;for(auto& item:jobs)ordered.push_back(item.second);
  std::sort(ordered.begin(),ordered.end(),[](const json& a,const json& b){return a.at("created").get<double>()>b.at("created").get<double>();});
  json result=json::array();for(auto& j:ordered){if(count--<=0)break;result.push_back(j);}return result;
 }
 if(op=="cancel"){
  auto id=r.at("id").get<std::string>();if(!jobs.count(id))throw Fault("JOB_NOT_FOUND",op,0,"Unknown task ID");auto& j=jobs.at(id);
  if(j["state"]=="queued"){auto next=j;next["state"]="cancelled";next["finished"]=timestamp();next["error"]={{"code","CANCELLED"},{"message","Cancelled before execution"}};saveJob(next);j=next;}
  else if(j["state"]=="running"||j["state"]=="cancelling"){
   dispatch({{"op","cancel"},{"request_id",id}});auto next=j;next["state"]="cancelling";saveJob(next);j=next;
  }
  return j;
 }
 if(op=="recover"){
  for(auto& item:jobs)if(item.second["state"]=="running"||item.second["state"]=="cancelling")throw Fault("BUSY",op,0,"Wait for active tasks to finish before recovery");
  if(!engine)throw Fault("EDITOR_NOT_READY",op,0,"Original engine is not loaded");
  // Keep admission locked until the independent Talker has been recreated.
  auto result=dispatch({{"op","recover"}});voiceCache=dispatch({{"op","voices"}});limitCache=dispatch({{"op","parameters"}});hostFault=nullptr;ready=true;jobsChanged.notify_one();return result;
 }
 if(!ready)throw Fault("EDITOR_NOT_READY",op,0,"Wait for the original editor to finish normal startup");
 if(op=="voices")return voiceCache;
 if(op=="parameters")return {{"native_bounds",limitCache},{"defaults",{{"volume",1.0},{"rate",1.0},{"pitch",1.0},{"emphasis",1.0},{"styles",json::object()}}}};
 if(op!="submit")throw Fault("UNKNOWN_OPERATION",op,0,"Unknown operation");
 std::string id=r.at("request_id"),text=r.at("text"),voice=r.at("voice"),language=r.value("language","standard");
 if(id.empty()||id.size()>100||id.find_first_not_of("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")!=std::string::npos)throw Fault("INVALID_REQUEST","id",0,"request_id must be a safe unique ID of 1..100 characters");
 if(text.empty()||text.size()>48000||text.find('\0')!=std::string::npos)throw Fault("INVALID_TEXT","submit",0,"Text must contain 1..48000 UTF-8 bytes without NUL");
 bool found=false;for(auto& v:voiceCache)if(v["id"]==voice&&v["available"]==true)found=true;
 if(!found)throw Fault("VOICE_NOT_INSTALLED","submit",0,"Voice is not available in the licensed editor");
 if(language!="standard"&&language!="kansai")throw Fault("INVALID_LANGUAGE","submit",0,"Unsupported language dictionary");
 auto params=r.value("parameters",json::object());if(!params.is_object())throw Fault("INVALID_PARAMETER","submit",0,"parameters must be an object");
 auto output=r.contains("output_path")?fs::u8path(r.at("output_path").get<std::string>()):stateRoot/"outputs"/(id+".wav");
 if(!output.is_absolute()||output.extension()!=L".wav")throw Fault("INVALID_OUTPUT","submit",0,"Absolute .wav output path required");
 output=output.lexically_normal();
 json request={{"request_id",id},{"text",text},{"voice",voice},{"language",language},{"parameters",params},{"output_path",utf8(output)}};
 if(jobs.count(id)){auto& prior=jobs.at(id);if(prior["request"]!=request)throw Fault("ID_CONFLICT","submit",0,"request_id already identifies different parameters");return prior;}
 if(pending.size()>=1000)throw Fault("QUEUE_FULL","submit",0,"Pending queue capacity reached");
 if(fs::exists(output)||fs::exists(fs::path(output.wstring()+L".partial")))throw Fault("OUTPUT_EXISTS","submit",0,"Output or partial output already exists");
 for(auto& item:jobs)if(!terminal(item.second["state"])&&item.second["output"]==utf8(output))throw Fault("OUTPUT_RESERVED","submit",0,"Another task reserved this output");
 json job={{"id",id},{"state","queued"},{"request",request},{"result",nullptr},{"error",nullptr},{"created",timestamp()},{"started",nullptr},{"finished",nullptr},{"output",utf8(output)}};
 saveJob(job);jobs.emplace(id,job);pending.push_back(id);jobsChanged.notify_one();return job;
}
static DWORD WINAPI dropinClient(void* h){
 HANDLE pipe=(HANDLE)h;std::array<char,65536> buffer{};DWORD got=0;
 if(ReadFile(pipe,buffer.data(),(DWORD)buffer.size(),&got,nullptr)){
  json response;
  try{response={{"ok",true},{"result",route(json::parse(buffer.data(),buffer.data()+got))}};}
  catch(const Fault& e){response={{"ok",false},{"error",errorInfo(e)}};}
  catch(const std::exception& e){response={{"ok",false},{"error",{{"code","INVALID_REQUEST"},{"message",e.what()}}}};}
  auto data=response.dump(-1,' ',false,json::error_handler_t::replace);
  if(data.size()>65535)data=R"({"ok":false,"error":{"code":"RESPONSE_TOO_LARGE","message":"Request fewer jobs"}})";
  DWORD written=0;WriteFile(pipe,data.data(),(DWORD)data.size(),&written,nullptr);FlushFileBuffers(pipe);
 }
 DisconnectNamedPipe(pipe);CloseHandle(pipe);return 0;
}
static DWORD WINAPI dropinServe(void*){
 auto name=L"\\\\.\\pipe\\AIVoice2Bridge2-"+std::to_wstring(GetCurrentProcessId());
 PSECURITY_DESCRIPTOR sd=nullptr;if(!ConvertStringSecurityDescriptorToSecurityDescriptorW(L"D:P(A;;GA;;;OW)",SDDL_REVISION_1,&sd,nullptr))return 1;
 SECURITY_ATTRIBUTES sa={sizeof(sa),sd,FALSE};
 for(;;){
  auto pipe=CreateNamedPipeW(name.c_str(),PIPE_ACCESS_DUPLEX,PIPE_TYPE_MESSAGE|PIPE_READMODE_MESSAGE|PIPE_WAIT|PIPE_REJECT_REMOTE_CLIENTS,16,65536,65536,1000,&sa);
  if(pipe==INVALID_HANDLE_VALUE)break;
  if(ConnectNamedPipe(pipe,nullptr)||GetLastError()==ERROR_PIPE_CONNECTED){auto t=CreateThread(nullptr,0,dropinClient,pipe,0,nullptr);if(t)CloseHandle(t);else CloseHandle(pipe);}else CloseHandle(pipe);
 }
 LocalFree(sd);return 0;
}
static DWORD WINAPI workQueue(void*){
 for(;;){
  std::string id;json request;
  {
   std::unique_lock<std::mutex> lock(jobsMutex);jobsChanged.wait(lock,[]{return ready&&!pending.empty();});id=pending.front();pending.pop_front();auto& j=jobs.at(id);
   if(j["state"]!="queued")continue;
   auto next=j;next["state"]="running";next["started"]=timestamp();
   try{saveJob(next);}catch(const Fault& e){hostFault=errorInfo(e);ready=false;pending.push_front(id);continue;}
   j=next;request=j["request"];request["op"]="synthesize";
  }
  json result=nullptr,error=nullptr;std::string status="succeeded";
  try{
   result=dispatch(request);auto path=fs::u8path(result.at("output_path").get<std::string>());result["sha256"]=sha256(path);result["file_bytes"]=fs::file_size(path);result["frames"]=result["pcm_bytes"].get<uint64_t>()/2;
  }catch(const Fault& e){error=errorInfo(e);status=e.code=="CANCELLED"?"cancelled":"failed";
   try{dispatch({{"op","recover"}});}catch(const Fault& recovery){std::lock_guard<std::mutex> lock(jobsMutex);hostFault=errorInfo(recovery);ready=false;}
  }catch(const std::exception& e){error={{"code","BRIDGE_ERROR"},{"message",e.what()}};status="failed";}
  {
   std::lock_guard<std::mutex> lock(jobsMutex);auto next=jobs.at(id);next["state"]=status;next["result"]=result;next["error"]=error;next["finished"]=timestamp();
   try{saveJob(next);jobs.at(id)=next;}catch(const Fault& e){hostFault=errorInfo(e);ready=false;}
  }
 }
}
static DWORD WINAPI initializeHost(void*){
 try{
  wchar_t exe[32768]{},local[32768]{};GetModuleFileNameW(nullptr,exe,32768);
  if(fs::path(exe).filename()!=L"aivoice.exe")return 0; // Merely loading the DLL into a client never starts a host.
  root=fs::path(exe).parent_path();auto n=GetEnvironmentVariableW(L"LOCALAPPDATA",local,32768);if(!n||n>=32768)return 1;
  stateRoot=fs::path(local)/"AIVoice2Bridge"/"v2";fs::create_directories(stateRoot/"jobs");fs::create_directories(stateRoot/"outputs");
  stateLock=CreateFileW((stateRoot/"host.lock").c_str(),GENERIC_READ|GENERIC_WRITE,0,nullptr,OPEN_ALWAYS,FILE_ATTRIBUTE_NORMAL,nullptr);if(stateLock==INVALID_HANDLE_VALUE)return 1;
  struct Pin{const wchar_t* file;const char* hash;};
  for(auto& pin:std::array<Pin,4>{{
   {L"aivoice.exe","928e476e5038d6e1403d3f98fc5c644677473b627126d89055756c6b1b81f0c7"},
   {L"data/app.so","0c344cd779d788fa1cb45d0f833995c93fd5e687569c795824e600d6b59e56b9"},
   {L"Lib/AITalk/aitalk_engine.dll","b565b146b0b4de9cc07bacafbf680847f966d47fec733a6cf376b4089b381bf9"},
   {L"aivoice2_window_size_original.dll","431767fa70d128427315b8b43a2be74a3da03a2d8a80679955522a917934ac4f"}
  }})if(sha256(root/pin.file)!=pin.hash)throw Fault("UNVERIFIED_EDITOR","integrity",0,"Editor version differs from verified 2.13.0 files");
  for(auto& entry:fs::directory_iterator(stateRoot/"jobs"))if(entry.path().extension()==L".json"){
   std::ifstream f(entry.path());json j;f>>j;f.close();std::string id=j.at("id");
   if(id.find_first_not_of("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")!=std::string::npos||entry.path().stem()!=fs::u8path(id))throw std::runtime_error("Invalid task journal name");
   if(j["state"]=="running"||j["state"]=="cancelling"){
    j["state"]="interrupted";j["finished"]=timestamp();j["error"]={{"code","EDITOR_EXITED"},{"message","Editor exited before task completion was committed; inspect output before retry"}};
    auto partial=fs::u8path(j.at("output").get<std::string>());partial+=L".partial";std::error_code cleanupError;fs::remove(partial,cleanupError);if(cleanupError)j["error"]["partial_cleanup_error"]=cleanupError.message();saveJob(j);
   }
   jobs.emplace(id,j);
  }
  std::vector<std::pair<double,std::string>> ordered;for(auto& item:jobs)if(item.second["state"]=="queued")ordered.emplace_back(item.second["created"].get<double>(),item.first);
  std::sort(ordered.begin(),ordered.end());for(auto& item:ordered)pending.push_back(item.second);
  auto server=CreateThread(nullptr,0,dropinServe,nullptr,0,nullptr);if(!server)throw std::runtime_error("Could not start in-process pipe listener");CloseHandle(server);
  journal(stateRoot/"editor-session.json",{{"pid",GetCurrentProcessId()},{"protocol",2},{"deployment","editor-drop-in-dll"},{"pipe","\\\\.\\pipe\\AIVoice2Bridge2-"+std::to_string(GetCurrentProcessId())},{"exe_path",utf8(fs::path(exe))}});
  for(;;){
   engine=GetModuleHandleW(L"aitalk_engine.dll");
   if(engine){try{auto v=dispatch({{"op","voices"}}),p=dispatch({{"op","parameters"}});std::lock_guard<std::mutex> lock(jobsMutex);voiceCache=v;limitCache=p;hostFault=nullptr;ready=true;break;}catch(const Fault& e){std::lock_guard<std::mutex> lock(jobsMutex);hostFault=errorInfo(e);}}
   Sleep(1000);
  }
  return workQueue(nullptr);
 }catch(const Fault& e){std::lock_guard<std::mutex> lock(jobsMutex);hostFault=errorInfo(e);}
 catch(const std::exception& e){std::lock_guard<std::mutex> lock(jobsMutex);hostFault={{"code","HOST_INITIALIZATION_ERROR"},{"message",e.what()}};}
 try{if(!stateRoot.empty())journal(stateRoot/"last-fault.json",hostFault);}catch(...){}
 return 1;
}
extern "C" __declspec(dllexport) unsigned AIVoice2Bridge_GetProtocolVersion(){return 2;}
extern "C" __declspec(dllexport) void WindowSizePluginRegisterWithRegistrar(void* registrar){
 wchar_t path[32768]{};GetModuleFileNameW(selfModule,path,32768);
 auto original=fs::path(path).parent_path()/L"aivoice2_window_size_original.dll";
 auto module=LoadLibraryExW(original.c_str(),nullptr,LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR|LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
 auto forward=module?reinterpret_cast<void(*)(void*)>(GetProcAddress(module,"WindowSizePluginRegisterWithRegistrar")):nullptr;
 if(!forward){RaiseFailFastException(nullptr,nullptr,0);return;}
 forward(registrar);
}
BOOL WINAPI DllMain(HMODULE mod,DWORD reason,void*){
 if(reason==DLL_PROCESS_ATTACH){selfModule=mod;DisableThreadLibraryCalls(mod);auto t=CreateThread(nullptr,0,initializeHost,nullptr,0,nullptr);if(t)CloseHandle(t);}
 return TRUE;
}
