import requests
r = requests.post('http://127.0.0.1:8080/analyze_async', data={'text':'x','analysis_type':'summary'}, files=[('files',('test.docx', b'Hello','application/vnd.openxmlformats-officedocument.wordprocessingml.document'))], timeout=30)
print(r.status_code)
print(r.text)
