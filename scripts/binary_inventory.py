import hashlib,json,re,struct
from pathlib import Path
ROOT=Path(r'C:\Program Files\AI\AIVoice2\AIVoice2Editor')
OUT=Path('evidence')
for name in ['aivoice.exe','data/app.so','Lib/AITalk/aitalk_engine.dll','uv.dll']:
 p=ROOT/name; b=p.read_bytes()
 strings=[{'offset':m.start(),'value':m.group().decode('ascii')} for m in re.finditer(rb'[\x20-\x7e]{6,}',b)]
 (OUT/(p.name+'.strings.json')).write_text(json.dumps(strings,ensure_ascii=False,indent=2),encoding='utf-8')
 print(name,len(b),hashlib.sha256(b).hexdigest(),b[:4])
 for s in strings:
  if re.search(r'(?i)Tts|synth|aisp|\.dll|\.net|socket|pipe|http|export|SaveAudio|Aitalk|VoiceList|localhost|127\.0\.0|TextTo|GetVoice',s['value']):
   print(hex(s['offset']),s['value'][:300])
