import { type Activity, type ActivityLog, diffMin, isOpen, type LogSource } from './models';

/** '지금' 버튼 한 번의 결과. */
export interface TapResult {
  /** 상태가 바뀌었는지. 이미 같은 상태면 false. */
  changed: boolean;
  /** 새로 시작한 상태. */
  started?: Activity;
  /** 이번 탭으로 끝난 기록. */
  ended?: ActivityLog;
  /** 10분 안에 같은 상태로 돌아와 앞 기록에 합쳤는지. */
  merged?: boolean;
}

let counter = 0;
const defaultId = (): string => `log-${Date.now()}-${counter++}`;

/**
 * '지금' 버튼 상태 전환. 화면 정의서 S-02와 기획서의 버튼 규칙을 구현한다.
 *
 * - 누르면 이전 상태 기록을 끝내고 새 상태 기록을 시작한다.
 * - 5초 안에는 되돌릴 수 있다.
 * - 다른 상태로 10분 미만 바꿨다가 원래 상태로 돌아오면, 중간 기록을 지우고
 *   앞 기록을 이어간다(잠깐 잘못 누른 경우와 짧은 중단을 하나로 합친다).
 */
export class NowTracker {
  readonly mergeMinutes: number;
  readonly undoSeconds: number;
  private readonly newId: () => string;
  private _logs: ActivityLog[];
  private undoSnapshot: ActivityLog[] | null = null;
  private lastTapAt: Date | null = null;

  constructor(opts: { logs?: ActivityLog[]; mergeMinutes?: number; undoSeconds?: number; idGenerator?: () => string } = {}) {
    this._logs = [...(opts.logs ?? [])];
    this.mergeMinutes = opts.mergeMinutes ?? 10;
    this.undoSeconds = opts.undoSeconds ?? 5;
    this.newId = opts.idGenerator ?? defaultId;
  }

  get logs(): ActivityLog[] {
    return [...this._logs];
  }

  get current(): ActivityLog | null {
    for (let i = this._logs.length - 1; i >= 0; i--) {
      if (isOpen(this._logs[i])) return this._logs[i];
    }
    return null;
  }

  canUndo(now: Date): boolean {
    return (
      this.undoSnapshot != null &&
      this.lastTapAt != null &&
      now.getTime() - this.lastTapAt.getTime() <= this.undoSeconds * 1000
    );
  }

  tap(activity: Activity, now: Date, opts: { source?: LogSource; allowUndo?: boolean } = {}): TapResult {
    const source = opts.source ?? 'button';
    const allowUndo = opts.allowUndo ?? true;
    const cur = this.current;
    if (cur && cur.activity === activity) return { changed: false };
    const snapshot = [...this._logs];

    // 짧은 중단 뒤 원래 상태로 복귀 → 합치기
    if (cur && diffMin(now, cur.start) < this.mergeMinutes) {
      const prevIndex = this.indexOfLastClosedBefore(cur);
      if (prevIndex != null) {
        const prev = this._logs[prevIndex];
        const gap = diffMin(now, prev.end!);
        if (prev.activity === activity && gap < this.mergeMinutes) {
          const next = this._logs.filter((l) => l !== cur);
          next[prevIndex] = { ...prev, end: null };
          this._logs = next;
          this.remember(snapshot, now, allowUndo);
          return { changed: true, started: activity, merged: true };
        }
      }
    }

    let ended: ActivityLog | undefined;
    if (cur) {
      const closed = { ...cur, end: now };
      ended = closed;
      this._logs = this._logs.map((l) => (l === cur ? closed : l));
    }
    this._logs = [
      ...this._logs,
      { id: this.newId(), activity, start: now, end: null, source, confirmed: true, snoozeCount: 0 },
    ];
    this.remember(snapshot, now, allowUndo);
    return { changed: true, started: activity, ended };
  }

  /** 현재 상태를 끝내기만 한다(예: 기상 알람 끄기, '오늘 마무리'). */
  stop(now: Date): ActivityLog | null {
    const cur = this.current;
    if (!cur) return null;
    const ended = { ...cur, end: now };
    this._logs = this._logs.map((l) => (l === cur ? ended : l));
    this.undoSnapshot = null;
    return ended;
  }

  /** 마지막 탭을 되돌린다. 5초가 지났으면 false. */
  undo(now: Date): boolean {
    if (!this.canUndo(now)) return false;
    this._logs = this.undoSnapshot!;
    this.undoSnapshot = null;
    this.lastTapAt = null;
    return true;
  }

  /** 위젯·단축어처럼 앱 밖에서 쌓인 탭을 시간순으로 반영한다. 되돌리기는 없다. */
  applyExternal(events: { activity: Activity; at: Date }[], source: LogSource = 'widget'): TapResult[] {
    const sorted = [...events].sort((a, b) => a.at.getTime() - b.at.getTime());
    return sorted.map((e) => this.tap(e.activity, e.at, { source, allowUndo: false }));
  }

  private indexOfLastClosedBefore(cur: ActivityLog): number | null {
    const idx = this._logs.indexOf(cur);
    for (let i = idx - 1; i >= 0; i--) {
      if (!isOpen(this._logs[i])) return i;
    }
    return null;
  }

  private remember(snapshot: ActivityLog[], now: Date, allowUndo: boolean): void {
    if (allowUndo) {
      this.undoSnapshot = snapshot;
      this.lastTapAt = now;
    } else {
      this.undoSnapshot = null;
      this.lastTapAt = null;
    }
  }
}
