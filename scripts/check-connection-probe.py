"""Exercise the connection tester against localhost only, with a synthetic key."""
import json
import pathlib
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

repo = pathlib.Path(__file__).resolve().parent.parent
subprocess.run(['swift', 'build', '--product', 'CodexMultiTests'], cwd=repo, check=True, stdout=subprocess.DEVNULL)
bin_dir = pathlib.Path(subprocess.check_output(['swift', 'build', '--show-bin-path'], cwd=repo, text=True).strip())
fixture = repo / '.build' / 'connection-probe-fixture'
objects = sorted((bin_dir / 'CodexMultiCore.build').glob('*.swift.o'))
subprocess.run(['swiftc', '-parse-as-library', '-I', str(bin_dir / 'Modules'), str(repo / 'scripts/connection-probe-fixture.swift'), *map(str, objects), '-o', str(fixture)], check=True)
observed = []

class Gateway(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get('Content-Length', 0))))
        observed.append((self.path, self.headers.get('Authorization'), body))
        route = self.path.split('/')[1]
        payload = {'object': 'response', 'id': 'resp_fixture', 'status': 'completed', 'output': []}
        code = 200
        if route == 'unauthorized':
            code = 401
            payload = {'error': 'SECRET-ECHO'}
        elif route == 'redirect':
            code = 307
        elif route == 'malformed':
            payload = {'error': 'SECRET-ECHO'}
        elif route == 'limited':
            payload.update(status='incomplete', incomplete_details={'reason': 'max_output_tokens'})
        elif route == 'oversized':
            payload['padding'] = 'x' * 300_000
        elif route == 'slow':
            time.sleep(3)
        data = json.dumps(payload).encode()
        try:
            self.send_response(code)
            if route == 'redirect':
                self.send_header('Location', '/redirect-target/v1/responses')
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass

server = ThreadingHTTPServer(('127.0.0.1', 0), Gateway)
threading.Thread(target=server.serve_forever, daemon=True).start()
cases = [('success', 'completed'), ('limited', 'limited'), ('unauthorized', 'error'),
         ('redirect', 'error'), ('malformed', 'error'), ('oversized', 'error'), ('slow', 'cancelled')]
try:
    for route, outcome in cases:
        start = time.monotonic()
        subprocess.run([str(fixture), f'http://127.0.0.1:{server.server_port}/{route}/v1', outcome], check=True, timeout=10, stdout=subprocess.DEVNULL)
        if route == 'slow':
            assert time.monotonic() - start < 2, 'Cancellation did not stop promptly'
        print(f'PASS connection probe: {route}')
    assert len(observed) == len(cases), 'Unexpected request or followed redirect'
    for (path, auth, body), (route, _) in zip(observed, cases):
        assert path == f'/{route}/v1/responses'
        assert auth == 'Bearer fixture-key-for-localhost-only'
        assert body == {'model': 'fixture/model-id', 'input': 'Reply with OK.', 'max_output_tokens': 64, 'stream': False, 'store': False}
    print('PASS exact request routing; no redirects, local files, or real credentials')
finally:
    server.shutdown()
    server.server_close()
