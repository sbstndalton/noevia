"""Real native LLMClient workload, without opening a Diary database or corpus."""
import json
import math
import os
import pathlib
from agent.llm import LLMClient

base = os.environ['NATIVE_QA_BASE'] + '/v1'
reference = json.loads(pathlib.Path(os.environ['NATIVE_QA_EMBED_REFERENCE']).read_text())
chat = LLMClient(base, chat_model='Gemma-4-E4B-it-GGUF', embed_model='nomic-embed-text-v1-GGUF', max_retries=1)
aux = LLMClient(base, chat_model='gemma-4-E2B-it-GGUF-UD-Q4_K_XL', max_retries=1)
try:
    vectors = chat.embed(reference['synthetic_inputs'])
    previous = sorted(reference['data'], key=lambda value: value['index'])
    cosine = []
    for current, old in zip(vectors, previous):
        other = old['embedding']
        assert len(current) == len(other) == 768
        similarity = sum(a*b for a,b in zip(current, other)) / math.sqrt(sum(a*a for a in current)*sum(b*b for b in other))
        # Backend versions can differ numerically. Pair this tolerance with
        # exact intended retrieval, including new queries against OLD vectors.
        assert similarity > .995, similarity
        cosine.append(similarity)
    def dot(a, b):
        return sum(x*y for x,y in zip(a,b))
    retrieval = []
    for index in range(8):
        query = vectors[10 + index]
        old_query = previous[10 + index]['embedding']
        old_rank = max(range(8), key=lambda i: dot(old_query, previous[2+i]['embedding']))
        cross_rank = max(range(8), key=lambda i: dot(query, previous[2+i]['embedding']))
        new_rank = max(range(8), key=lambda i: dot(query, vectors[2+i]))
        assert old_rank == cross_rank == new_rank == index, (index, old_rank, cross_rank, new_rank)
        retrieval.append({'expected':index,'old':old_rank,'new_query_old_index':cross_rank,'new':new_rank})
    auxiliary = aux.chat([{'role':'user', 'content':'Synthetic fixture. Reply with exactly AUX_OK.'}],max_tokens=2048,temperature=0)
    assert 'AUX_OK' in auxiliary, auxiliary
    events = []
    answer = chat.chat_stream([{'role':'user','content':'Synthetic fixture. Reply with exactly DIARY_CLIENT_OK.'}],events.append,temperature=0)
    assert 'DIARY_CLIENT_OK' in answer, answer
    assert events, events
    again = chat.embed(['search_query: synthetic amber'])
    assert len(again) == 1 and len(again[0]) == 768
    print(json.dumps({'embedding_cosine_to_lemonade':cosine,'retrieval':retrieval,'auxiliary':str(auxiliary),'auxiliary_reasoning_chars':len(auxiliary.reasoning),'streamed_chat':str(answer),'embedding_reload':True}))
finally:
    chat.close()
    aux.close()
