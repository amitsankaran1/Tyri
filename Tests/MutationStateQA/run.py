from pathlib import Path
import subprocess,tempfile,os
r=Path(__file__).resolve().parents[2]
def method(f,name):
 s=subprocess.check_output(['git','show',os.environ['QA_REVISION']+':'+f],cwd=r,text=True) if os.environ.get('QA_REVISION') else (r/f).read_text()
 a=s.index('func '+name);b=s.index('{',a);i=b+1;n=1
 while n:n+=(s[i]=='{')-(s[i]=='}');i+=1
 return s[a:i]
with tempfile.TemporaryDirectory(prefix='tyri-mutation-state-') as d:
 d=Path(d);s=''
 for name,f,methods in [('ScreenTimeManager','Tyri/Services/ScreenTimeManager.swift',['disableAllBlocks()','isBlockActive(']),('GroupEditor','Tyri/Views/AppGroupEditorView.swift',['deleteGroup()']),('BlockEditor','Tyri/Views/BlockEditorView.swift',['deleteBlock()'])]:
  s+='extension '+name+' {\n'+'\n'.join(method(f,m) for m in methods)+'\n}\n'
 p=d/'Production.swift';p.write_text('import Foundation\n'+s)
 subprocess.run(['swiftc','-parse-as-library','-module-cache-path',str(d/'cache'),str(p),str(Path(__file__).with_name('main.swift')),str(r/'Shared/EnforcementTransaction.swift'),'-o',str(d/'run')],check=True)
 subprocess.run([str(d/'run')],check=True)
