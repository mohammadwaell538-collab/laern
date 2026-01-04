from fastapi.testclient import TestClient
import proxy_server

client = TestClient(proxy_server.app)

def test_local_fallback_on_gemini_error():
    # Force call_gemini to return an error string so the fallback is used
    original_call = proxy_server.call_gemini
    proxy_server.call_gemini = lambda prompt: ("خطأ: محاكاة خطأ Gemini", 0, 0)

    resp = client.post("/analyze", data={"text":"نص للاختبار","youtube":"","analysis_type":"summary"})
    assert resp.status_code == 200
    data = resp.json()
    assert data.get("fallback") is True
    assert "تم استخدام محلل محلي" in data.get("note", "")

    # restore
    proxy_server.call_gemini = original_call
