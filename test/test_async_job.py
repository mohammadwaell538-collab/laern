from fastapi.testclient import TestClient
import proxy_server
import time

client = TestClient(proxy_server.app)


def test_analyze_async_text_job():
    # Start an async job with simple text
    r = client.post('/analyze_async', data={'text': 'هذا نص تجريبي لتحليل طويل نسبياً. ' * 5, 'analysis_type': 'summary'})
    assert r.status_code == 200
    job_id = r.json().get('job_id')
    assert job_id

    # Poll for completion (wait up to 5s)
    for _ in range(20):
        s = client.get(f'/job/{job_id}/status')
        assert s.status_code == 200
        status = s.json().get('status')
        if status == 'completed':
            break
        time.sleep(0.25)
    else:
        assert False, 'Job did not complete in time'

    res = client.get(f'/job/{job_id}/result')
    assert res.status_code == 200
    data = res.json()
    assert 'analysis' in data
    assert data['main_topics'] >= 0
    assert data['key_points'] >= 0
