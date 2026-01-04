import requests

resp = requests.post('http://localhost:8080/analyze', data={'text':'نص اختبار خارجي','youtube':'','analysis_type':'summary'})
print(resp.status_code)
print(resp.text)
