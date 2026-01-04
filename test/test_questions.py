from fastapi.testclient import TestClient
import proxy_server
import time

client = TestClient(proxy_server.app)


def test_interactive_questions_in_result():
    r = client.post('/analyze_async', data={'text': 'هذه فقرة قصيرة للاختبار. تحتوي على فكرة رئيسية واحدة.', 'analysis_type':'summary'})
    job_id = r.json().get('job_id')

    for _ in range(20):
        s = client.get(f'/job/{job_id}/status')
        if s.json().get('status') == 'completed':
            break
        time.sleep(0.2)

    res = client.get(f'/job/{job_id}/result')
    assert res.status_code == 200
    data = res.json()
    assert 'interactive_questions' in data
    assert isinstance(data['interactive_questions'], list)
    assert len(data['interactive_questions']) >= 20
    print('questions count:', len(data['interactive_questions']))
