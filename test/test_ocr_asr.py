from fastapi.testclient import TestClient
import proxy_server
import io

client = TestClient(proxy_server.app)


def test_ocr_and_audio_transcription_monkeypatched():
    # Monkeypatch extractors to simulate OCR and ASR
    original_img = proxy_server.extract_text_from_image
    original_trans = proxy_server.transcribe_audio_bytes

    proxy_server.extract_text_from_image = lambda b: 'نص من صورة للاختبار'
    proxy_server.transcribe_audio_bytes = lambda b: 'نص من ملف صوتي'

    # Create fake image and audio uploads
    files = [
        ('files', ('test.png', b'fakeimagebytes', 'image/png')),
        ('files', ('sample.mp3', b'fakeaudiobytes', 'audio/mpeg')),
    ]

    r = client.post('/analyze_async', data={'text':'', 'analysis_type':'summary'}, files=files)
    assert r.status_code == 200
    job_id = r.json().get('job_id')
    assert job_id

    # Poll for completion
    import time
    for _ in range(40):
        s = client.get(f'/job/{job_id}/status')
        if s.json().get('status') == 'completed':
            break
        time.sleep(0.1)
    res = client.get(f'/job/{job_id}/result')
    assert res.status_code == 200
    data = res.json()
    assert 'نص من صورة' in data['analysis'] or 'نص من ملف' in data['analysis']

    # restore
    proxy_server.extract_text_from_image = original_img
    proxy_server.transcribe_audio_bytes = original_trans
