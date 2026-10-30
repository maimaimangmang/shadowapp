"""Cross-process launch/edit/trash exclusion and OS lock release after a killed launcher."""
import pathlib
import queue
import signal
import subprocess
import tempfile
import threading

repo = pathlib.Path(__file__).resolve().parent.parent
subprocess.run(['swift', 'build', '--product', 'CodexMultiTests'], cwd=repo, check=True, stdout=subprocess.DEVNULL)
bin_dir = pathlib.Path(subprocess.check_output(['swift', 'build', '--show-bin-path'], cwd=repo, text=True).strip())
fixture = repo / '.build' / 'operation-lease-fixture'
objects = sorted((bin_dir / 'CodexMultiCore.build').glob('*.swift.o'))
subprocess.run(['swiftc', '-I', str(bin_dir / 'Modules'), str(repo / 'scripts/operation-lease-fixture.swift'), *map(str, objects), '-o', str(fixture)], check=True)
with tempfile.TemporaryDirectory(prefix='codex-lease-check-') as root:
    def run(mode, *args):
        return subprocess.check_output([str(fixture), mode, root, *args], text=True, timeout=10).strip()
    profile = run('create')
    before = {p.relative_to(root): p.read_bytes() for p in pathlib.Path(root).rglob('*') if p.is_file() and p.name != '.registry.lock'}
    holder = subprocess.Popen([str(fixture), 'hold', root, profile], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    ready = queue.Queue()
    threading.Thread(target=lambda: ready.put(holder.stdout.readline()), daemon=True).start()
    try:
        assert ready.get(timeout=10).strip() == 'READY'
        assert run('probe', profile) == 'BUSY'
        assert run('mutate', profile) == 'BLOCKED'
        assert all((pathlib.Path(root) / path).read_bytes() == content for path, content in before.items())
        print('PASS cross-process launch/edit/trash exclusion preserves profile data')
        holder.send_signal(signal.SIGKILL)
        holder.wait(timeout=5)
        assert run('probe', profile) == 'AVAILABLE'
        assert run('probe', profile) == 'AVAILABLE'
        print('PASS killed launcher releases its lease without deleting lock files')
    finally:
        if holder.poll() is None:
            holder.kill()
            holder.wait(timeout=5)
