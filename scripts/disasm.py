import sys,pefile,capstone,re
from pathlib import Path
p=pefile.PE(r'C:\Program Files\AI\AIVoice2\AIVoice2Editor\Lib\AITalk\aitalk_engine.dll')
base=p.OPTIONAL_HEADER.ImageBase
cs=capstone.Cs(capstone.CS_ARCH_X86,capstone.CS_MODE_64)
exports={s.name.decode():s.address for s in p.DIRECTORY_ENTRY_EXPORT.symbols if s.name}
for name in sys.argv[1:]:
 rva=exports.get(name)
 if rva is None:rva=int(name,16)-base
 print('\nFUNCTION',name,hex(base+rva),'file',hex(p.get_offset_from_rva(rva)))
 end=next((e.struct.EndAddress for e in p.DIRECTORY_ENTRY_EXCEPTION if e.struct.BeginAddress<=rva<e.struct.EndAddress),rva+256)
 for ins in cs.disasm(p.get_data(rva,end-rva),base+rva):
  suffix=''
  for match in re.finditer(r'rip ([+-]) (0x[0-9a-f]+)',ins.op_str):
   a=ins.address+ins.size+(1 if match[1]=='+' else -1)*int(match[2],16)-base
   try:
    v=p.get_data(a,150).split(b'\0')[0]
    if len(v)>3 and all(32<=c<127 for c in v):suffix+=' ; '+v.decode()
   except Exception:pass
  print(hex(ins.address),ins.mnemonic,ins.op_str+suffix)
