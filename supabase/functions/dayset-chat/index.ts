// DaySet '말로 일정 바꾸기' AI 함수(Supabase Edge Function, Deno).
// 앱·웹이 보낸 말과 지금 일정 요약을 Claude에 넘겨, 일정 바꾸기 목록(JSON)만 돌려받는다.
// 일정을 직접 바꾸지 않는다: 앱이 목록을 미리 보여 주고 사용자가 '바꾸기'를 눌러야 적용한다.
//
// 설정: Supabase 대시보드 → Edge Functions → Secrets 에 ANTHROPIC_API_KEY 넣기.
// 로그인한 사용자만 부를 수 있다. 새 공개 키(sb_publishable)는 플랫폼 JWT 확인과 맞지 않아
// 'Verify JWT'는 끄고(config.toml), 여기서 로그인 토큰을 Auth 서버에 물어 확인한다.

const MODEL = Deno.env.get('DAYSET_AI_MODEL') ?? 'claude-haiku-5-5';
const KEY = Deno.env.get('ANTHROPIC_API_KEY') ?? '';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';

/** 로그인 토큰이 이 프로젝트의 사용자인지 Auth 서버에 묻는다. */
async function signedIn(req: Request): Promise<boolean> {
  const auth = req.headers.get('authorization') ?? '';
  const apikey = req.headers.get('apikey') ?? '';
  if (!auth.startsWith('Bearer ') || !SUPABASE_URL || !apikey) return false;
  try {
    const r = await fetch(`${SUPABASE_URL}/auth/v1/user`, { headers: { Authorization: auth, apikey } });
    if (!r.ok) return false;
    const u = await r.json();
    return typeof u?.id === 'string';
  } catch {
    return false;
  }
}

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const TOOL = {
  name: 'propose_edits',
  description: '사용자의 말을 DaySet 일정 바꾸기 목록으로 만든다. 모르면 edits를 비우고 reply에 되묻는다.',
  input_schema: {
    type: 'object',
    properties: {
      reply: { type: 'string', description: '사용자에게 보여 줄 짧은 한국어 답(사실 + 다음 행동, 해요체).' },
      edits: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            kind: { type: 'string', enum: ['habit', 'wake', 'event-add', 'event-move', 'event-delete', 'task-add', 'reset'] },
            day: { type: 'string', description: 'YYYY-MM-DD (habit·wake·reset)' },
            title: { type: 'string', description: 'habit: 목표에 있는 습관 이름 그대로 / event-add·task-add: 제목' },
            scope: { type: 'string', enum: ['day', 'every'], description: 'day=그날만, every=매일' },
            start: { type: 'string', description: 'habit·wake: HH:MM / event-add·event-move: YYYY-MM-DDTHH:MM' },
            end: { type: 'string', description: 'event-add·event-move: YYYY-MM-DDTHH:MM' },
            minutes: { type: 'integer', description: 'habit 길이 또는 task-add 걸리는 시간(분)' },
            skip: { type: 'boolean', description: 'habit: 그날 빼기' },
            id: { type: 'string', description: 'event-move·event-delete: 캘린더 일정 id' },
            taskType: { type: 'string', enum: ['work', 'assignment', 'homework', 'personal'] },
            due: { type: 'string', description: 'task-add 마감 YYYY-MM-DD' },
          },
          required: ['kind'],
        },
      },
    },
    required: ['reply', 'edits'],
  },
};

const SYSTEM = `너는 생활습관 앱 DaySet의 일정 도우미다. 사용자의 말을 일정 바꾸기 목록으로만 바꾼다.
규칙:
- 바꿀 수 있는 것: 습관(식사·운동) 시작·길이·그날 빼기(그날만/매일), 기상 알람(그날만/매일), 캘린더 일정 넣기·옮기기·지우기, 할 일 넣기, 그날 바꾼 것 되돌리기.
- 수면 블록·잠금 일정·가져온 캘린더 일정(events의 imported: true)은 바꾸지 않는다.
- 습관 이름은 context.habits에 있는 이름을 그대로 쓴다. 캘린더 일정 id는 context.events의 id만 쓴다.
- 날짜를 말하지 않았으면 오늘. 단, 그 습관이 오늘 이미 끝났으면 내일.
- '매일·앞으로·항상'이면 scope=every, 아니면 day.
- 오전·오후를 말하지 않았으면 그 습관의 지금 시각에 가까운 쪽으로.
- 읽을 수 없거나 범위 밖이면 edits를 비우고 reply로 짧게 되묻는다.
- reply는 해요체 한 문장, 진단·치료 같은 의료 표현 금지.`;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
  if (!KEY) return json(503, { error: 'ai_not_configured' });
  if (!(await signedIn(req))) return json(401, { error: 'sign_in_required' });
  let body: { text?: string; context?: unknown };
  try {
    body = await req.json();
  } catch {
    return json(400, { error: 'bad_json' });
  }
  const text = String(body.text ?? '').slice(0, 400);
  if (!text.trim()) return json(400, { error: 'empty' });
  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: { 'x-api-key': KEY, 'anthropic-version': '2023-06-01', 'content-type': 'application/json' },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 800,
      system: SYSTEM,
      tools: [TOOL],
      tool_choice: { type: 'tool', name: 'propose_edits' },
      messages: [{ role: 'user', content: `context: ${JSON.stringify(body.context ?? {})}\n\n사용자: ${text}` }],
    }),
  });
  if (!res.ok) return json(502, { error: 'ai_failed', status: res.status });
  const out = await res.json();
  const use = (out.content ?? []).find((c: { type: string }) => c.type === 'tool_use');
  if (!use) return json(502, { error: 'no_tool_use' });
  return json(200, use.input);
});
