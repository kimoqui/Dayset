// 테스트용 가짜 계정 서버.

/** 메모리 안 가짜 서버: Supabase Auth(GoTrue)·PostgREST에서 쓰는 길만 흉내 낸다. */
export function fakeServer() {
  const users = new Map<string, { id: string; password: string }>();
  const tokens = new Map<string, string>(); // access → userId
  const refresh = new Map<string, string>(); // refresh → userId
  const rows = new Map<string, { state: unknown; rev: number; device: string | null; updated_at: string }>();
  let n = 0;
  let down = false;
  const session = (id: string, email: string) => {
    const a = `a${++n}`;
    const r = `r${n}`;
    tokens.set(a, id);
    refresh.set(r, id);
    return { access_token: a, refresh_token: r, expires_in: 3600, user: { id, email } };
  };
  const res = (status: number, body: unknown) => new Response(body == null ? null : JSON.stringify(body), { status });
  const fetcher = async (input: string, init: RequestInit = {}) => {
    if (down) throw new TypeError('Failed to fetch');
    const url = new URL(input);
    const method = init.method ?? 'GET';
    const body = init.body ? JSON.parse(String(init.body)) : {};
    const auth = String((init.headers as Record<string, string>).Authorization ?? '').replace('Bearer ', '');
    const who = tokens.get(auth);
    if (url.pathname === '/auth/v1/signup') {
      if (users.has(body.email)) return res(422, { code: 422, error_code: 'user_already_exists', msg: 'User already registered' });
      if (String(body.password).length < 6) return res(422, { error_code: 'weak_password', msg: 'Password should be at least 6 characters.' });
      const id = `u${users.size + 1}`;
      users.set(body.email, { id, password: body.password });
      return res(200, session(id, body.email));
    }
    if (url.pathname === '/auth/v1/token') {
      if (url.searchParams.get('grant_type') === 'password') {
        const u = users.get(body.email);
        if (!u || u.password !== body.password) return res(400, { error_code: 'invalid_credentials', msg: 'Invalid login credentials' });
        return res(200, session(u.id, body.email));
      }
      const id = refresh.get(body.refresh_token);
      if (!id) return res(400, { error_code: 'refresh_token_not_found', msg: 'Invalid Refresh Token: Refresh Token Not Found' });
      refresh.delete(body.refresh_token);
      return res(200, session(id, [...users.entries()].find(([, v]) => v.id === id)![0]));
    }
    if (url.pathname === '/auth/v1/logout') return res(204, null);
    if (url.pathname === '/auth/v1/recover') return res(200, {});
    if (url.pathname === '/rest/v1/dayset_state') {
      if (!who) return res(401, { message: 'JWT expired' });
      const userEq = url.searchParams.get('user_id')?.replace('eq.', '');
      if (userEq && userEq !== who) return res(200, []); // 행 수준 보안: 남의 행은 안 보인다
      const row = rows.get(who);
      if (method === 'GET') return res(200, row ? [{ ...row }] : []);
      if (method === 'POST') {
        if (body.user_id !== who) return res(403, { message: 'new row violates row-level security policy' });
        if (row) return res(409, { code: '23505', message: 'duplicate key value violates unique constraint' });
        rows.set(who, { state: body.state, rev: body.rev, device: body.device, updated_at: new Date().toISOString() });
        return res(201, null);
      }
      if (method === 'PATCH') {
        const rev = Number(url.searchParams.get('rev')?.replace('eq.', ''));
        if (!row || row.rev !== rev) return res(200, []);
        const next = { ...row, ...body };
        rows.set(who, next);
        return res(200, [next]);
      }
      if (method === 'DELETE') {
        rows.delete(who);
        return res(204, null);
      }
    }
    return res(404, { message: 'not found' });
  };
  return { fetcher, rows, users, setDown: (v: boolean) => (down = v) };
}

