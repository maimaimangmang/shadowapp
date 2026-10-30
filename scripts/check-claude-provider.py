#!/usr/bin/env python3
"""Opt-in: native Claude gateway discovery plus launcher Messages probes, synthetic keys only."""
import http.server,json,pathlib,subprocess,tempfile,threading
ROOT=pathlib.Path(__file__).resolve().parents[1]
seen=[]
class Gateway(http.server.BaseHTTPRequestHandler):
    def log_message(self,*args): pass
    def respond(self,value,status=200):
        data=json.dumps(value).encode(); self.send_response(status)
        self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
    def do_GET(self):
        if '/v1/models' not in self.path: self.respond({},404);return
        index='1' if self.path.startswith('/profile1/') else '2'
        seen.append(('GET',index,self.path,self.headers.get('Authorization')==f'Bearer fixture-claude-key-{index}'))
        self.respond({'data':[{'id':'fixture/claude-sonnet-4-5','display_name':'Fixture Claude','type':'model'}],'has_more':False})
    def do_POST(self):
        body=json.loads(self.rfile.read(int(self.headers.get('Content-Length','0'))))
        index='1' if self.path.startswith('/profile1/') else '2'
        ok=self.path==f'/profile{index}/v1/messages' and self.headers.get('Authorization')==f'Bearer fixture-claude-key-{index}' and body.get('model')=='fixture/claude-sonnet-4-5' and self.headers.get('anthropic-version')=='2023-06-01'
        seen.append(('POST',index,self.path,ok))
        self.respond({'id':'msg_fixture','type':'message','role':'assistant','model':body.get('model'),'content':[{'type':'text','text':'OK'}],'stop_reason':'end_turn','usage':{'input_tokens':1,'output_tokens':1}})
subprocess.run(['swift','build','--product','CodexMulti'],cwd=ROOT,check=True,stdout=subprocess.DEVNULL)
bin_dir=pathlib.Path(subprocess.check_output(['swift','build','--show-bin-path'],cwd=ROOT,text=True).strip())
objects=list((bin_dir/'CodexMultiCore.build').glob('*.swift.o'))
exe=ROOT/'.build/claude-provider-fixture'
subprocess.run(['swiftc','-parse-as-library','-target',f'{__import__("platform").machine()}-apple-macosx13.0',str(ROOT/'scripts/claude-provider-fixture.swift'),'-I',str(bin_dir/'Modules'),*map(str,objects),'-o',str(exe)],check=True)
server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Gateway)
threading.Thread(target=server.serve_forever,daemon=True).start()
root=pathlib.Path(tempfile.mkdtemp(prefix='claude-provider-check-'))
try:
    result=subprocess.run([str(exe),str(root),f'http://127.0.0.1:{server.server_port}'],cwd=ROOT,timeout=150)
    if result.returncode: raise RuntimeError(f'Fixture failed; preserved {root}')
    for i in ['1','2']:
        assert any(m=='GET' and idx==i and ok for m,idx,p,ok in seen),f'No authenticated native model discovery for profile {i}'
        assert any(m=='POST' and idx==i and ok for m,idx,p,ok in seen),f'No valid Messages probe for profile {i}'
    print('PASS native Claude loads separate gateway endpoints/keys and discovers configured models')
    print('PASS launcher Messages tests send exact models and parse responses; no real chat or credentials used')
    __import__('shutil').rmtree(root)
finally: server.shutdown()
