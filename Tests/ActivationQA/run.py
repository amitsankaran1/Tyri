from pathlib import Path
import subprocess,tempfile,os
repo=Path(__file__).resolve().parents[2]
def source(f):
 return subprocess.check_output(['git','show',os.environ['QA_REVISION']+':'+f],cwd=repo,text=True) if os.environ.get('QA_REVISION') else (repo/f).read_text()
def method(s,name):
 start=s.index('    private func '+name+'() {');body=s.index('{',start);depth=1;i=body+1
 while depth:
  depth += (s[i]=='{')-(s[i]=='}');i+=1
 return s[start:i].replace('private func','func')
with tempfile.TemporaryDirectory(prefix='tyri-activation-qa-') as d:
 d=Path(d);p=d/'ProductionMethods.swift'
 p.write_text('extension Probe {\n'+method(source('Tyri/Views/BlockEditorView.swift'),'save')+'\n'+method(source('Tyri/Views/HomeView.swift'),'refresh')+'\n}')
 subprocess.run(['swiftc','-parse-as-library','-module-cache-path',str(d/'cache'),str(Path(__file__).with_name('Doubles.swift')),str(p),*([str(repo/'Shared/EnforcementTransaction.swift')] if not os.environ.get('QA_REVISION') else []),'-o',str(d/'run')],check=True)
 result=subprocess.run([str(d/'run')],capture_output=True,text=True,check=True,timeout=25)
 print(result.stdout,end="")
 if "FAIL:" in result.stdout: raise SystemExit(1)
