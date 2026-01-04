from fastapi.testclient import TestClient
import proxy_server

client = TestClient(proxy_server.app)

resp = client.post("/analyze", data={"text":"نص تجريبي للذكاء الاصطناعي","youtube":"","analysis_type":"summary"})
print("STATUS:", resp.status_code)
print(resp.text)
