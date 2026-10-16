import hashlib,json,pefile
from pathlib import Path
root=Path(r'C:\Program Files\AI\AIVoice2\AIVoice2Editor');result=[]
for path in sorted(root.rglob('*')):
 if path.suffix.lower() not in ('.exe','.dll','.so') or not path.is_file():continue
 b=path.read_bytes();row={'path':str(path.relative_to(root)),'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest()}
 if b[:2]==b'MZ':
  p=pefile.PE(data=b,fast_load=True);cli=p.OPTIONAL_HEADER.DATA_DIRECTORY[14]
  row.update({'format':'PE','machine':hex(p.FILE_HEADER.Machine),'dll':bool(p.FILE_HEADER.Characteristics&0x2000),'managed':bool(cli.VirtualAddress and cli.Size)})
 elif b[:4]==b'\x7fELF':row.update({'format':'ELF','managed':False,'machine':int.from_bytes(b[18:20],'little')})
 result.append(row)
Path('evidence/binary-inventory.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print({'binaries':len(result),'managed':sum(bool(x.get('managed')) for x in result),'native':sum(not x.get('managed') for x in result)})
