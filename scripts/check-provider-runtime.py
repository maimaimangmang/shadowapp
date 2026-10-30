# -*- coding: utf-8 -*-
import json, os, pathlib, queue, signal, subprocess, sys, tempfile, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

repo = pathlib.Path(__file__).resolve().parent.parent
os.chdir(repo)
binary = sys.argv[1] if len(sys.argv) > 1 else '/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex'
subprocess.run(['swift', 'build', '--product', 'CodexMultiTests'], check=True, stdout=subprocess.DEVNULL)
bin_dir = pathlib.Path(subprocess.check_output(['swift', 'build', '--show-bin-path'], text=True).strip())
fixture = repo / '.build' / 'provider-fixture'
objects = sorted((bin_dir / 'CodexMultiCore.build').glob('*.swift.o'))
subprocess.run(['swiftc', '-I', str(bin_dir / 'Modules'), str(repo / 'scripts/provider-fixture.swift'), *map(str, objects), '-o', str(fixture)], check=True)
observed = []
class Gateway(BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get('Content-Length', 0))))
        observed.append((self.path, self.headers.get('Authorization'), body))
        item = {'id':'msg_fixture', 'type':'message','status':'completed','role':'assistant','content':[{'type':'output_text','text':'LOCAL_PROVIDER_OK','annotations':[]}]}
        events = [
            ('response.created', {'type':'response.created','response':{'id':'resp_fixture','object':'response','status':'in_progress','output':[]}}),
            ('response.output_item.added', {'type':'response.output_item.added','output_index':0,'item':dict(item,status='in_progress',content=[])}),
            ('response.output_text.delta', {'type':'response.output_text.delta','item_id':'msg_fixture','output_index':0,'content_index':0,'delta':'LOCAL_PROVIDER_OK'}),
            ('response.output_item.done', {'type':'response.output_item.done','output_index':0,'item':item}),
            ('response.completed', {'type':'response.completed','response':{'id':'resp_fixture','object':'response','status':'completed','output':[item],'usage':{'input_tokens':10,'output_tokens':3,'total_tokens':13}}})]
        data = ''.join('event: '+event+'\ndata: '+json.dumps(payload)+'\n\n' for event,payload in events).encode()
        self.send_response(200); self.send_header('Content-Type','text/event-stream'); self.send_header('Content-Length',str(len(data))); self.end_headers(); self.wfile.write(data)
    def do_GET(self):
        self.send_response(404); self.end_headers()

server=ThreadingHTTPServer(('127.0.0.1',0),Gateway)
threading.Thread(target=server.serve_forever,daemon=True).start()
with tempfile.TemporaryDirectory(prefix='codex-provider-runtime-') as temp:
    base='http://127.0.0.1:'+str(server.server_port)+'/v1'
    codex_home=subprocess.check_output([str(fixture),temp+'/launcher',base],text=True).strip()
    env={k:v for k,v in os.environ.items() if not any(w in k for w in ('OPENAI','CODEX','TOKEN','API_KEY'))}
    env.update({'HOME':temp,'CODEX_HOME':codex_home,'CODEX_SQLITE_HOME':codex_home})
    app=subprocess.Popen([binary,'app-server','--strict-config','--stdio'],cwd=temp,env=env,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=True,start_new_session=True)
    messages=queue.Queue()
    def read():
        for line in app.stdout:
            try: messages.put(json.loads(line))
            except ValueError: pass
    threading.Thread(target=read,daemon=True).start()
    def request(id, method, params):
        app.stdin.write(json.dumps({'id':id,'method':method,'params':params})+'\n');app.stdin.flush()
        while True:
            response=messages.get(timeout=15)
            if response.get('id')==id:
                assert 'error' not in response, method+' returned an error'
                return response.get('result')
    try:
        request(1,'initialize',{'clientInfo':{'name':'codex_multi_fixture','version':'0.1'},'capabilities':{'experimentalApi':True}})
        app.stdin.write(json.dumps({'method':'initialized'})+'\n');app.stdin.flush()
        account=request(2,'account/read',{'refreshToken':False})
        assert account['account']['type']=='apiKey', 'API auth mode was not recognized'
        config=request(3,'config/read',{'includeLayers':False})['config']
        assert config['model']=='fixture/model-id' and config['model_provider']=='codex_multi'
        print('PASS installed app-server recognizes API key auth and selected model/provider')
        request(4,'config/value/write',{'keyPath':'model','value':'fixture/client-selected','mergeStrategy':'replace','filePath':codex_home+'/config.toml'})
        request(5,'config/value/write',{'keyPath':'model_reasoning_effort','value':'low','mergeStrategy':'upsert','filePath':codex_home+'/config.toml'})
    finally:
        app.terminate()
        try: app.wait(timeout=5)
        except subprocess.TimeoutExpired: app.kill();app.wait()
        try: os.killpg(app.pid, signal.SIGKILL)
        except ProcessLookupError: pass
    auth_before=pathlib.Path(codex_home, 'auth.json').read_bytes()
    subprocess.run([str(fixture),temp+'/launcher',base,'update'],check=True,stdout=subprocess.DEVNULL)
    assert pathlib.Path(codex_home, 'auth.json').read_bytes()==auth_before, 'Saved key was changed'
    assert 'model_reasoning_effort = "low"' in pathlib.Path(codex_home, 'config.toml').read_text(), 'Client settings were lost'
    print('PASS launcher edits the client-rewritten model configuration and preserves saved key/settings')
    runner=subprocess.Popen([binary,'exec','--skip-git-repo-check','--ephemeral','--json','--sandbox','read-only','Reply with LOCAL_PROVIDER_OK. Do not use any tools.'],cwd=temp,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
    try:
        stdout, _ = runner.communicate(timeout=30)
    finally:
        try: os.killpg(runner.pid, signal.SIGKILL)
        except ProcessLookupError: pass
        runner.wait()
    # Isolated runtime helpers can outlive the main CLI briefly; let them reap before cleanup.
    time.sleep(0.2)
    assert observed, 'No request received at the local gateway'
    assert all(path=='/v1/responses' for path,_,_ in observed), 'Unexpected endpoint'
    assert all(auth=='Bearer fixture-key-for-localhost-only' for _,auth,_ in observed), 'Wrong credential routing'
    assert all(body['model']=='fixture/updated-model' for _,_,body in observed), 'Wrong model ID'
    assert runner.returncode==0 and 'LOCAL_PROVIDER_OK' in stdout, 'Model response did not finish successfully'
    assert all('BEGIN CODEX MULTI PROFILE CONTEXT' in json.dumps(body) for _,_,body in observed), 'Profile guidance was not sent to the model'
    assert all(codex_home + '/config.toml' in json.dumps(body) for _,_,body in observed), 'Guidance does not identify this profile configuration'
    print('PASS installed Codex includes isolated-profile guidance in model requests')
    print('PASS installed Codex sends the profile key and exact model ID to /v1/responses and completes a local response')
server.shutdown()
