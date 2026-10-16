#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <sddl.h>
#include <array>
#include <atomic>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <set>
#include <string>
#include <vector>
#include "../tools/json.hpp"
using json=nlohmann::json;
namespace fs=std::filesystem;
static HMODULE engine;
static fs::path root;
static void* talker=nullptr;
static void* sink=nullptr;
static std::mutex engineMutex;
static std::atomic<bool> cancelFlag{false};
static std::atomic<bool> busy{false};
static std::mutex cancelMutex;
static std::string activeId;
static std::set<std::string> cancelledIds;
static std::set<std::string> loaded;
struct Fault:std::runtime_error{std::string code,stage;int native;Fault(std::string c,std::string s,int n,std::string m):runtime_error(m),code(c),stage(s),native(n){}};
template<class F> F api(const char* name){auto p=GetProcAddress(engine,name);if(!p)throw Fault("ABI_MISMATCH",name,0,"Required export missing");return reinterpret_cast<F>(p);}
static void check(int rc,const char* stage){if(rc!=0)throw Fault("ENGINE_ERROR",stage,rc,"Original engine returned an error");}
static std::string utf8(fs::path p){return p.u8string();}
struct Event{int kind;int pad;void* payload;};
struct Buffers{unsigned char* pcm;uint64_t bytes;unsigned char* markers;uint64_t markerCount;};
struct Capture{
 std::array<unsigned char,262144> pcm{};
 // Each marker is 80 bytes in the hash-pinned 2.13.0 engine (see ABI evidence).
 std::array<unsigned char,80*1024> markers{};
 std::ofstream file;
 uint64_t bytes=0,requests=0,done=0;
 bool failed=false;
};
static int callback(void* user,Event* ev) noexcept{
 auto& c=*static_cast<Capture*>(user);
 if(cancelFlag.load(std::memory_order_relaxed))return 1;
 try{
  if(ev->kind==3){auto b=(Buffers*)ev->payload;b->pcm=c.pcm.data();b->bytes=c.pcm.size();b->markers=c.markers.data();b->markerCount=1024;c.requests++;}
  if(ev->kind==4){auto b=(Buffers*)ev->payload;if(b->pcm!=c.pcm.data()||b->bytes>c.pcm.size()||b->bytes%2){c.failed=true;return 2;}
   c.file.write((char*)b->pcm,b->bytes);if(!c.file){c.failed=true;return 2;}c.bytes+=b->bytes;c.done++;
  }
  return 0;
 }catch(...){c.failed=true;return 2;}
}
static void destroy(){
 if(talker){api<void(*)(void*)>("ai_Talker_delete")(talker);talker=nullptr;}
 if(sink){api<void(*)(void*)>("ai_TtsCallbackSink_delete")(sink);sink=nullptr;}
 loaded.clear();
}
static void ensure(){
 if(talker)return;
 if(!engine)throw Fault("EDITOR_NOT_READY","initialize",0,"Original editor has not loaded the synthesis engine");
 talker=api<void*(*)()>("ai_Talker_new")();
 if(!talker)throw Fault("EDITOR_NOT_READY","ai_Talker_new",0,"Editor engine is not initialized; complete normal editor startup");
 try{
  for(auto key:{"standard","kansai"}){
   auto p=root/"Lang"/key/(std::string(key)+".aildic");if(!fs::exists(p))continue;
   check(api<int(*)(void*,const char*,const char*,int)>("ai_Talker_loadLangDic")(talker,key,utf8(p).c_str(),1),"ai_Talker_loadLangDic");
  }
 }catch(...){destroy();throw;}
}
static void loadVoice(const std::string& key){
 ensure();if(loaded.count(key))return;
 if(key.empty()||key.find_first_not_of("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")!=std::string::npos)throw Fault("INVALID_VOICE","voice",0,"Invalid voice ID");
 auto dir=root/"Voice"/key;auto p=dir/(key+".aivdic");auto lic=dir/"voice.lic";
 if(!fs::is_regular_file(p)||!fs::is_regular_file(lic))throw Fault("VOICE_NOT_INSTALLED","voice",0,"Voice files are absent");
 // These are ordinary library calls. All activation and license checks remain in the original engine.
 check(api<int(*)(void*,const char*,const char*,int,const char*)>("ai_Talker_loadDic")(talker,key.c_str(),utf8(p).c_str(),1,utf8(lic).c_str()),"ai_Talker_loadDic");
 loaded.insert(key);
}
static json voices(){
 ensure();json result=json::array();
 for(auto& entry:fs::directory_iterator(root/"Voice")){
  if(!entry.is_directory())continue;
  auto key=entry.path().filename().u8string();
  if(!fs::exists(entry.path()/(key+".aivdic")))continue;
  json v={{"id",key}};
  try{
   loadVoice(key);
   auto name=api<const char*(*)(void*,const char*)>("ai_Talker_getVoiceNameByKey")(talker,key.c_str());
   v["name"]=name?name:key;
   v["sample_rate"]=api<int(*)(void*,const char*)>("ai_Talker_getVoiceFsByKey")(talker,key.c_str());
   int count=api<int(*)(void*,const char*)>("ai_Talker_getStyleColorSizeByKey")(talker,key.c_str());
   v["styles"]=json::array();
   if(count<0||count>128)throw Fault("ABI_MISMATCH","styles",count,"Unexpected style count");
   for(int i=0;i<count;i++){
    char label[1024]{};
    int labelResult=api<int(*)(void*,const char*,int,char*,size_t)>("ai_Talker_getStyleColorLabelByKey")(talker,key.c_str(),i,label,sizeof(label));
    if(labelResult<0)check(labelResult,"ai_Talker_getStyleColorLabelByKey");
    v["styles"].push_back(label);
   }
   v["available"]=true;
  }catch(const Fault& e){v["available"]=false;v["error"]={{"code",e.code},{"stage",e.stage},{"native_code",e.native}};}
  result.push_back(v);
 }
 return result;
}
static json parameterLimits(){
 ensure();void* config=api<void*(*)()>("ai_TalkerConfig_new")();
 if(!config)throw Fault("ENGINE_ERROR","parameters",0,"Could not create configuration");
 json limits;
 try{
  auto get=[&](const char* n){return api<double(*)(void*)>(n)(config);};
  limits={{"rate",{{"min",get("ai_TalkerConfig_getRateMin")},{"max",get("ai_TalkerConfig_getRateMax")}}},{"pitch",{{"min",get("ai_TalkerConfig_getPitchMin")},{"max",get("ai_TalkerConfig_getPitchMax")}}},{"emphasis",{{"max",get("ai_TalkerConfig_getEmphMax")}}}};
 }catch(...){api<void(*)(void*)>("ai_TalkerConfig_delete")(config);throw;}
 api<void(*)(void*)>("ai_TalkerConfig_delete")(config);return limits;
}
static void put16(std::ostream& f,uint16_t v){f.put(char(v));f.put(char(v>>8));}
static void put32(std::ostream& f,uint32_t v){put16(f,uint16_t(v));put16(f,uint16_t(v>>16));}
static void wavHeader(std::ostream& f,uint32_t bytes,int rate){f.seekp(0);f.write("RIFF",4);put32(f,36+bytes);f.write("WAVEfmt ",8);put32(f,16);put16(f,1);put16(f,1);put32(f,rate);put32(f,rate*2);put16(f,2);put16(f,16);f.write("data",4);put32(f,bytes);}
static json synthesize(const json& r){
 auto start=std::chrono::steady_clock::now();
 std::string voice=r.at("voice"),text=r.at("text"),language=r.value("language","standard");
 if(text.empty()||text.size()>48000||text.find('\0')!=std::string::npos)throw Fault("INVALID_TEXT","validate",0,"Text must contain 1..48000 UTF-8 bytes without NUL");
 if(language!="standard"&&language!="kansai")throw Fault("INVALID_LANGUAGE","validate",0,"Language must be standard or kansai");
 auto output=fs::u8path(r.at("output_path").get<std::string>());
 if(!output.is_absolute()||output.extension()!=L".wav")throw Fault("INVALID_OUTPUT","validate",0,"An absolute .wav output path is required");
 if(fs::exists(output))throw Fault("OUTPUT_EXISTS","validate",0,"Output exists; bridge never overwrites it");
 auto temp=output;temp+=L".partial";
 if(fs::exists(temp))throw Fault("OUTPUT_EXISTS","validate",0,"Partial output already exists");
 loadVoice(voice);
 check(api<int(*)(void*,const char*)>("ai_Talker_selectVoiceDic")(talker,voice.c_str()),"ai_Talker_selectVoiceDic");
 check(api<int(*)(void*,const char*)>("ai_Talker_selectLangDic")(talker,language.c_str()),"ai_Talker_selectLangDic");
 int rate=api<int(*)(void*,const char*)>("ai_Talker_getVoiceFsByKey")(talker,voice.c_str());
 if(rate!=48000)throw Fault("UNSUPPORTED_FORMAT","sample_rate",rate,"Only the verified 48 kHz voices are admitted");
 auto params=r.value("parameters",json::object());
 for(auto it=params.begin();it!=params.end();++it)if(it.key()!="volume"&&it.key()!="rate"&&it.key()!="pitch"&&it.key()!="emphasis"&&it.key()!="styles")throw Fault("INVALID_PARAMETER","validate",0,"Unknown voice parameter: "+it.key());
 void* config=api<void*(*)()>("ai_TalkerConfig_new")();
 if(!config)throw Fault("ENGINE_ERROR","config",0,"Could not create configuration");
 try{
  for(auto item:{std::pair{"volume","Volume"},{"rate","Rate"},{"pitch","Pitch"},{"emphasis","Emph"}}){
   double val=params.value(item.first,1.0);
   if(!std::isfinite(val))throw Fault("INVALID_PARAMETER","validate",0,"Parameter must be finite");
   auto name=std::string("ai_TalkerConfig_set")+item.second;
   check(api<int(*)(void*,double)>(name.c_str())(config,val),name.c_str());
  }
  auto styles=params.value("styles",json::object());
  if(!styles.is_object())throw Fault("INVALID_PARAMETER","styles",0,"styles must be a map from native labels to strengths");
  double sum=0;for(auto& item:styles.items()){double x=item.value();if(!std::isfinite(x)||x<0||x>1)throw Fault("INVALID_PARAMETER","styles",0,"Style strengths must be in [0,1]");sum+=x;}
  if(sum>1.000001)throw Fault("INVALID_PARAMETER","styles",0,"Sum of style strengths must not exceed 1");
  std::string styleJson;
  for(auto& item:styles.items())styleJson+=item.key()+":"+std::to_string(item.value().get<double>())+",";
  check(api<int(*)(void*,const char*)>("ai_TalkerConfig_setStyleColor")(config,styleJson.c_str()),"ai_TalkerConfig_setStyleColor");
  check(api<int(*)(void*,void*)>("ai_Talker_setDefaultConfig")(talker,config),"ai_Talker_setDefaultConfig");
 }catch(...){api<void(*)(void*)>("ai_TalkerConfig_delete")(config);throw;}
 api<void(*)(void*)>("ai_TalkerConfig_delete")(config);
 Capture capture;fs::create_directories(output.parent_path());
 capture.file.open(temp,std::ios::binary|std::ios::trunc);
 if(!capture.file)throw Fault("OUTPUT_IO_ERROR","open",0,"Could not open output");
 wavHeader(capture.file,0,rate);
 sink=api<void*(*)(void*,void*)>("ai_TtsCallbackSink_new")((void*)callback,&capture);
 if(!sink)throw Fault("ENGINE_ERROR","sink",0,"Could not create callback sink");
 int rc=0;
 try{
  check(api<int(*)(void*,void*)>("ai_Talker_setSink")(talker,sink),"ai_Talker_setSink");
  rc=api<int(*)(void*,const char*,int)>("ai_Talker_talk")(talker,text.c_str(),0);
  if(cancelFlag)throw Fault("CANCELLED","synthesize",rc,"Task was cancelled");
  if(capture.failed)throw Fault("OUTPUT_IO_ERROR","callback",rc,"Audio callback failed");
  check(rc,"ai_Talker_talk");
  if(!capture.bytes||capture.bytes>0xfffffff0)throw Fault("EMPTY_AUDIO","synthesize",0,"Invalid WAV data length");
  wavHeader(capture.file,(uint32_t)capture.bytes,rate);capture.file.flush();
  if(!capture.file)throw Fault("OUTPUT_IO_ERROR","finalize",0,"WAV write failed");
  capture.file.close();
  // Detach before destroying the sink; Talker retains a borrowed pointer.
  check(api<int(*)(void*,void*)>("ai_Talker_setSink")(talker,nullptr),"detach_sink");
  api<void(*)(void*)>("ai_TtsCallbackSink_delete")(sink);sink=nullptr;
  fs::rename(temp,output);
 }catch(...){
  capture.file.close();api<int(*)(void*,void*)>("ai_Talker_setSink")(talker,nullptr);
  if(sink){api<void(*)(void*)>("ai_TtsCallbackSink_delete")(sink);sink=nullptr;}
  std::error_code ec;fs::remove(temp,ec);throw;
 }
 return {{"output_path",utf8(output)},{"pcm_bytes",capture.bytes},{"sample_rate",rate},{"channels",1},{"sample_width",2},{"duration_seconds",capture.bytes/(rate*2.0)},{"elapsed_seconds",std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count()},{"buffer_requests",capture.requests},{"buffer_completions",capture.done},{"parameters",params}};
}
static json dispatch(const json& r){
 auto op=r.at("op").get<std::string>();
 if(op=="cancel"){
  std::lock_guard<std::mutex> lock(cancelMutex);auto id=r.value("request_id",std::string());
  if(id.empty()||id==activeId)cancelFlag=true;else cancelledIds.insert(id);
  return {{"cancel_requested",true}};
 }
 std::lock_guard<std::mutex> engineLock(engineMutex);
 struct Busy{Busy(){busy=true;}~Busy(){busy=false;}} guard;
 if(op=="voices")return voices();
 if(op=="parameters")return parameterLimits();
 if(op=="synthesize"){
  {std::lock_guard<std::mutex> lock(cancelMutex);activeId=r.value("request_id",std::string());cancelFlag=cancelledIds.erase(activeId)>0;}
  try{auto result=synthesize(r);std::lock_guard<std::mutex> lock(cancelMutex);activeId.clear();return result;}
  catch(...){std::lock_guard<std::mutex> lock(cancelMutex);activeId.clear();throw;}
 }
 if(op=="recover"){destroy();ensure();return {{"recovered",true}};}
 throw Fault("UNKNOWN_OPERATION","dispatch",0,"Unknown operation");
}
