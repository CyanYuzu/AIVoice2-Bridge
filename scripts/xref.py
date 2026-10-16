import pefile,capstone,sys
p=pefile.PE(r'C:\Program Files\AI\AIVoice2\AIVoice2Editor\Lib\AITalk\aitalk_engine.dll')
cs=capstone.Cs(capstone.CS_ARCH_X86,capstone.CS_MODE_64);cs.detail=True
base=p.OPTIONAL_HEADER.ImageBase
targets=[base+p.get_rva_from_offset(int(x,16)) for x in sys.argv[1:]]
for s in p.sections:
 if not s.Characteristics&0x20000000:continue
 for ins in cs.disasm(s.get_data(),base+s.VirtualAddress):
  for o in ins.operands:
   if o.type==capstone.x86.X86_OP_MEM and o.mem.base==capstone.x86.X86_REG_RIP and ins.address+ins.size+o.mem.disp in targets:
    fun=next((e.struct.BeginAddress for e in p.DIRECTORY_ENTRY_EXCEPTION if e.struct.BeginAddress<=ins.address-base<e.struct.EndAddress),0)
    print(hex(ins.address),ins.mnemonic,ins.op_str,'function',hex(base+fun))
