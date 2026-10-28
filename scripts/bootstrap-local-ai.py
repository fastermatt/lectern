#!/usr/bin/env python3
"""Fetch and verify the pinned optional inference runtime. No model downloads."""
import hashlib, json, os, platform, shutil, subprocess, tarfile, tempfile, urllib.request
from pathlib import Path, PurePosixPath
ROOT = Path(__file__).resolve().parent.parent
VENDOR = ROOT / 'Vendor/LocalAI'
URL = 'https://github.com/ggml-org/llama.cpp/releases/download/b11968/llama-b11968-bin-macos-arm64.tar.gz'
DIGEST = '74b7034262407e60acdc507508f260ba50fcba0cdf6a42fe74b21fb8b5088fa6'

def main():
    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        raise SystemExit('Packaging the local engine requires an Apple Silicon Mac. Core source builds do not need this step.')
    records = json.loads((VENDOR/'provenance.json').read_text())['files']
    def valid():
        return all((VENDOR/r['file']).is_file() and hashlib.sha256((VENDOR/r['file']).read_bytes()).hexdigest() == r['sha256'] for r in records)
    if not valid():
        with tempfile.TemporaryDirectory(prefix='lectern-runtime-') as tmp:
            archive=Path(tmp)/'runtime.tar.gz'
            with urllib.request.urlopen(URL, timeout=60) as response, archive.open('wb') as out:
                total=0
                while chunk := response.read(1024*1024):
                    total += len(chunk)
                    if total > 25_000_000: raise SystemExit('Runtime exceeded the expected download bound.')
                    out.write(chunk)
            if hashlib.sha256(archive.read_bytes()).hexdigest() != DIGEST:
                raise SystemExit('Runtime archive checksum failed. Nothing installed.')
            with tarfile.open(archive) as tar:
                members={PurePosixPath(m.name).name:m for m in tar.getmembers() if m.isfile() or m.issym()}
                staged=Path(tmp)/'verified';staged.mkdir()
                for record in records:
                    name=record['file'];member=members[name]
                    data=tar.extractfile(member).read()
                    if hashlib.sha256(data).hexdigest()!=record['sha256']: raise SystemExit('Runtime file checksum failed: '+name)
                    (staged/name).write_bytes(data)
                    (staged/name).chmod(0o755 if name=='llama-server' or name.endswith('.dylib') else 0o644)
                for name,member in members.items():
                    if member.issym() and name.endswith('.dylib'):
                        target=member.linkname
                        if '/' in target or target in ['.', '..']: raise SystemExit('Unsafe runtime library link')
                        (staged/name).symlink_to(target)
                for path in staged.iterdir():
                    if path.is_symlink() and not path.resolve().is_relative_to(staged.resolve()): raise SystemExit('Library link escapes runtime')
                    if path.is_symlink() and not path.exists(): raise SystemExit('Broken runtime library link')
                VENDOR.mkdir(parents=True,exist_ok=True)
                for path in staged.iterdir():
                    dest=VENDOR/path.name
                    if dest.exists() or dest.is_symlink():dest.unlink()
                    if path.is_symlink():dest.symlink_to(os.readlink(path))
                    else:shutil.copy2(path,dest)
    env=dict(os.environ);env.setdefault('DEVELOPER_DIR','/Applications/Xcode.app/Contents/Developer')
    subprocess.run(['/usr/bin/xcrun','clang','-O2','-arch','arm64','-mmacosx-version-min=14.0',str(ROOT/'scripts/local-ai-runner.c'),'-o',str(VENDOR/'lectern-model-runner')],check=True,env=env)
    print('Pinned runtime verified and launcher built. Model downloads remain optional.')
if __name__=='__main__':main()
