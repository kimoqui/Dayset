// 계정 연동: 이메일 계정으로 로그인하면 기록 전체(백업과 같은 JSON)를 서버(Supabase)에 두고 웹·앱이 함께 쓴다.
// SDK 없이 HTTP로 부른다(앱 버전 lib/platform/cloud.dart와 같은 규칙).
//
// 서버 표: dayset_state(user_id, state jsonb, rev, device, updated_at) — 행 수준 보안으로 자기 행만 읽고 쓴다.
// 동기화 규칙(마지막에 쓴 쪽이 이기되, 모르고 덮어쓰지 않는다):
//  - rev: 서버에 쓸 때마다 1씩 올린다. 기기는 마지막으로 맞춘 rev를 기억한다.
//  - 올리기: 서버 rev가 내가 아는 rev와 같을 때만 쓴다(조건부 PATCH). 아니면 '충돌'.
//  - 받기: 서버 rev가 더 크고 이 기기에 안 올린 변경이 없으면 서버 기록으로 바꾼다.
//  - 충돌(양쪽 다 바뀜, 또는 처음 연결할 때 양쪽에 기록이 있음): 사용자가 고른다. 버리는 쪽은 지우지 않고 보관한다.

export interface CloudConfig {
  url: string;
  key: string;
}

export interface Session {
  accessToken: string;
  refreshToken: string;
  /** 만료 시각(ms). */
  expiresAt: number;
  userId: string;
  email: string;
}

export interface RemoteState {
  state: unknown;
  rev: number;
  updatedAt: string;
  device: string | null;
}

export type CloudErrorCode = 'config' | 'network' | 'auth' | 'exists' | 'weak' | 'confirm' | 'rate' | 'server' | 'email';

export class CloudError extends Error {
  constructor(
    public code: CloudErrorCode,
    message: string,
  ) {
    super(message);
  }
}

const TEXT: Record<CloudErrorCode, string> = {
  config: '서버가 아직 준비되지 않았어요',
  network: '인터넷 연결을 확인해 주세요',
  auth: '이메일이나 비밀번호가 맞지 않아요',
  exists: '이미 가입한 이메일이에요. 로그인해 주세요',
  weak: '비밀번호는 6자 이상이어야 해요',
  confirm: '메일함에서 가입 확인 링크를 누른 뒤 로그인해 주세요',
  rate: '요청이 많아요. 잠시 후 다시 해 주세요',
  server: '서버에서 처리하지 못했어요. 잠시 후 다시 해 주세요',
  email: '이메일 주소를 확인해 주세요',
};

export const errorText = (e: unknown): string => (e instanceof CloudError ? e.message : TEXT.server);

/** 서버 오류 글을 사용자 문구로 바꾼다. */
export function classify(status: number, body: { msg?: string; message?: string; error_description?: string; error?: string; error_code?: string; code?: string }): CloudError {
  const raw = `${body.error_code ?? ''} ${body.code ?? ''} ${body.msg ?? ''} ${body.message ?? ''} ${body.error_description ?? ''} ${body.error ?? ''}`.toLowerCase();
  const code: CloudErrorCode =
    status === 429 || raw.includes('rate limit') || raw.includes('over_request')
      ? 'rate'
      : raw.includes('already registered') || raw.includes('user_already_exists') || raw.includes('already exists')
        ? 'exists'
        : raw.includes('not confirmed') || raw.includes('email_not_confirmed')
          ? 'confirm'
          : raw.includes('password') && (raw.includes('least') || raw.includes('weak') || raw.includes('short'))
            ? 'weak'
            : raw.includes('invalid login') || raw.includes('invalid_credentials') || raw.includes('invalid grant') || raw.includes('refresh token') || status === 401
              ? 'auth'
              : raw.includes('email') && (raw.includes('invalid') || raw.includes('format'))
                ? 'email'
                : 'server';
  return new CloudError(code, TEXT[code]);
}

type Fetch = (input: string, init?: RequestInit) => Promise<Response>;

export class CloudClient {
  constructor(
    private cfg: CloudConfig,
    private fetcher: Fetch = (i, o) => fetch(i, o),
  ) {}

  get ready(): boolean {
    return !!this.cfg.url && !!this.cfg.key;
  }

  private async call(path: string, init: RequestInit & { token?: string } = {}): Promise<{ status: number; json: unknown }> {
    if (!this.ready) throw new CloudError('config', TEXT.config);
    const headers: Record<string, string> = { apikey: this.cfg.key, 'Content-Type': 'application/json', ...((init.headers as Record<string, string>) ?? {}) };
    headers.Authorization = `Bearer ${init.token ?? this.cfg.key}`;
    let res: Response;
    try {
      res = await this.fetcher(`${this.cfg.url.replace(/\/+$/, '')}${path}`, { ...init, headers });
    } catch {
      throw new CloudError('network', TEXT.network);
    }
    const text = await res.text().catch(() => '');
    let json: unknown = null;
    try {
      json = text ? JSON.parse(text) : null;
    } catch {
      json = null;
    }
    if (!res.ok) throw classify(res.status, (json ?? {}) as Record<string, string>);
    return { status: res.status, json };
  }

  private toSession(j: { access_token?: string; refresh_token?: string; expires_in?: number; expires_at?: number; user?: { id: string; email?: string } }, now: number, email: string): Session {
    if (!j.access_token || !j.refresh_token || !j.user) throw new CloudError('server', TEXT.server);
    const expiresAt = j.expires_at ? j.expires_at * 1000 : now + (j.expires_in ?? 3600) * 1000;
    return { accessToken: j.access_token, refreshToken: j.refresh_token, expiresAt, userId: j.user.id, email: j.user.email ?? email };
  }

  /** 가입. 메일 확인을 켜 둔 서버면 'confirm'(로그인 전 메일 확인 필요). */
  async signUp(email: string, password: string, now = Date.now()): Promise<Session | 'confirm'> {
    if (password.length < 6) throw new CloudError('weak', TEXT.weak);
    const { json } = await this.call('/auth/v1/signup', { method: 'POST', body: JSON.stringify({ email: email.trim(), password }) });
    const j = json as { access_token?: string; user?: { identities?: unknown[] }; identities?: unknown[] };
    if (!j.access_token) {
      // 이미 가입한 이메일이면 빈 identities가 온다.
      const ids = j.user?.identities ?? j.identities;
      if (Array.isArray(ids) && ids.length === 0) throw new CloudError('exists', TEXT.exists);
      return 'confirm';
    }
    return this.toSession(json as never, now, email);
  }

  async signIn(email: string, password: string, now = Date.now()): Promise<Session> {
    const { json } = await this.call('/auth/v1/token?grant_type=password', { method: 'POST', body: JSON.stringify({ email: email.trim(), password }) });
    return this.toSession(json as never, now, email);
  }

  async refresh(s: Session, now = Date.now()): Promise<Session> {
    const { json } = await this.call('/auth/v1/token?grant_type=refresh_token', { method: 'POST', body: JSON.stringify({ refresh_token: s.refreshToken }) });
    return this.toSession(json as never, now, s.email);
  }

  async signOut(s: Session): Promise<void> {
    await this.call('/auth/v1/logout', { method: 'POST', token: s.accessToken }).catch(() => undefined);
  }

  async resetPassword(email: string): Promise<void> {
    await this.call('/auth/v1/recover', { method: 'POST', body: JSON.stringify({ email: email.trim() }) });
  }

  async fetchState(s: Session): Promise<RemoteState | null> {
    const { json } = await this.call(`/rest/v1/dayset_state?select=state,rev,updated_at,device&user_id=eq.${s.userId}`, { token: s.accessToken });
    const row = Array.isArray(json) ? (json[0] as { state: unknown; rev: number; updated_at: string; device: string | null } | undefined) : undefined;
    return row ? { state: row.state, rev: Number(row.rev), updatedAt: row.updated_at, device: row.device } : null;
  }

  /** 처음 올리기. 이미 행이 있으면 null(충돌). */
  async createState(s: Session, state: unknown, device: string): Promise<number | null> {
    try {
      await this.call('/rest/v1/dayset_state', {
        method: 'POST',
        token: s.accessToken,
        headers: { Prefer: 'return=minimal' },
        body: JSON.stringify({ user_id: s.userId, state, rev: 1, device }),
      });
      return 1;
    } catch (e) {
      if (e instanceof CloudError && (e.code === 'exists' || e.code === 'server')) {
        // 409(이미 있음)는 충돌로 본다.
        const remote = await this.fetchState(s);
        if (remote) return null;
      }
      throw e;
    }
  }

  /** 서버 rev가 baseRev일 때만 바꾼다. 바꿨으면 새 rev, 다른 기기가 먼저 바꿨으면 null. */
  async updateState(s: Session, state: unknown, baseRev: number, device: string, nowIso = new Date().toISOString()): Promise<number | null> {
    const { json } = await this.call(`/rest/v1/dayset_state?user_id=eq.${s.userId}&rev=eq.${baseRev}`, {
      method: 'PATCH',
      token: s.accessToken,
      headers: { Prefer: 'return=representation' },
      body: JSON.stringify({ state, rev: baseRev + 1, device, updated_at: nowIso }),
    });
    return Array.isArray(json) && json.length ? baseRev + 1 : null;
  }

  async deleteState(s: Session): Promise<void> {
    await this.call(`/rest/v1/dayset_state?user_id=eq.${s.userId}`, { method: 'DELETE', token: s.accessToken });
  }

  /** 말로 일정 바꾸기: 서버 AI 함수(dayset-chat)에 말과 일정 요약을 보내고 바꾸기 목록(JSON)을 받는다. */
  async askChat(s: Session, text: string, context: unknown): Promise<unknown> {
    const { json } = await this.call('/functions/v1/dayset-chat', { method: 'POST', token: s.accessToken, body: JSON.stringify({ text, context }) });
    return json;
  }
}

// ---------------------------------------------------------------------------
// 동기화 판단(순수 함수: 무엇을 할지만 정한다)
// ---------------------------------------------------------------------------

/** 이 기기가 기억하는 동기화 상태(계정마다). */
export interface SyncMeta {
  userId: string;
  /** 마지막으로 서버와 맞춘 rev(0 = 아직 맞춘 적 없음). */
  rev: number;
  /** 마지막으로 맞춘 뒤 이 기기에서 바뀐 것이 있는지. */
  dirty: boolean;
  /** 마지막으로 맞춘 시각(ms). */
  syncedAt: number | null;
}

export type SyncPlan =
  | { kind: 'create' }
  | { kind: 'push'; baseRev: number }
  | { kind: 'pull'; remote: RemoteState }
  | { kind: 'conflict'; remote: RemoteState; first: boolean }
  | { kind: 'none' };

/**
 * 무엇을 할지 정한다.
 * localHasData: 이 기기에 쓸 만한 기록이 있는지(시작했는지).
 */
export function planSync(meta: SyncMeta, remote: RemoteState | null, localHasData: boolean): SyncPlan {
  if (!remote) return localHasData ? { kind: 'create' } : { kind: 'none' };
  if (meta.rev === 0) {
    // 이 계정과 처음 맞춤: 이 기기가 비어 있으면 서버 기록을 받고, 둘 다 있으면 고르게 한다.
    return localHasData ? { kind: 'conflict', remote, first: true } : { kind: 'pull', remote };
  }
  if (remote.rev === meta.rev) return meta.dirty ? { kind: 'push', baseRev: meta.rev } : { kind: 'none' };
  if (remote.rev > meta.rev) return meta.dirty ? { kind: 'conflict', remote, first: false } : { kind: 'pull', remote };
  // 서버 rev가 더 작다(서버 기록을 지웠다 다시 만든 경우 등): 이 기기 것을 올린다.
  return { kind: 'push', baseRev: remote.rev };
}
