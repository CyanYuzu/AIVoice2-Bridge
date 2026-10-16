import {Client} from '../tools/rea/node_modules/@modelcontextprotocol/client/dist/index.mjs';
import {StdioClientTransport} from '../tools/rea/node_modules/@modelcontextprotocol/client/dist/stdio.mjs';
import fs from 'node:fs';import path from 'node:path';
const out=path.resolve('evidence/rea-native');fs.mkdirSync(out,{recursive:true});
const client=new Client({name:'aivoice2-local-investigation',version:'1.0.0'});
const transport=new StdioClientTransport({command:process.execPath,args:[path.resolve('tools/rea/node_modules/rea-agents/scripts/rea.mjs'),'mcp'],env:{...process.env,GHIDRA_INSTALL_DIR:path.resolve('tools/ghidra/ghidra_12.1.4_PUBLIC'),JAVA_HOME:'C:\\Program Files\\Java\\jdk-23'}});
await client.connect(transport);
const call=async(name,args,label)=>{console.log(name,label);const r=await client.callTool({name,arguments:args},{timeout:600000});fs.writeFileSync(path.join(out,label+'.json'),JSON.stringify(r,null,2));if(r.isError)console.log(JSON.stringify(r).slice(0,1000));return r;};
try{
 await call('open_binary',{path:'C:\\Program Files\\AI\\AIVoice2\\AIVoice2Editor\\Lib\\AITalk\\aitalk_engine.dll',provider_id:'ghidra'},'open');
 for(const p of ['ai_Talker_talk','ai_Talker_loadDic','ai_TalkerConfig_setRate','ai_TalkerConfig_setStyleColor','ai_Talker_getStyleColorLabelByKey','0x1800ceeb0','0x1800ce4f0','0x1800ce638','0x1800e9330','0x1800d8030','0x1800d99e0','0x1800e8a10'])await call('procedure_pseudo_code',{procedure:p},p);
 await call('close_binary',{},'close');
}finally{await client.close();}
