import subprocess, sys
p = subprocess.Popen([sys.executable, 'scripts/test_mock_uploads.py'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
out, err = p.communicate()
print('EXITCODE', p.returncode)
if out:
    print('--- STDOUT ---')
    print(out.decode('utf-8', errors='replace'))
if err:
    print('--- STDERR ---')
    print(err.decode('utf-8', errors='replace'))
