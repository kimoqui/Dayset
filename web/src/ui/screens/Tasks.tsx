import { type ReactNode, useMemo, useRef, useState } from 'react';
import { addDays, blockMinutes, dateKey, focusByType, formatDuration, formatHm, isAfter, isBefore, TASK_TYPE, type TaskItem, type TaskType } from '../../engine/models';
import { planFor } from '../../app/derive';
import { LEARN_DAYS, learnPrefs, suggestOrder } from '../../app/priorityModel';
import type { AppState } from '../../app/state';
import { calibrationFor, calibrationText } from '../../app/duration';
import { objectParticle } from '../../engine/coaching';
import { deleteTask, dismissOrderSuggestion, extendTask, getState, newId, now as clockNow, type PlanChange, reorderTasks, saveTask, taskPlanMinutes, toggleTaskDone } from '../../app/store';
import { Icon, Sheet } from '../kit';
import { haptic } from '../motion';

export type ToastFn = (text: string, undo?: boolean | 'plan') => void;

/** 다시 짠 일정에서 그 할 일이 언제 들어갔는지(예: '오늘 14:00', 하는 중이면 '지금'). */
function whereNow(id: string): string | null {
  const st = getState();
  const t = clockNow();
  for (const [k, label] of [[dateKey(t), '오늘'], [dateKey(addDays(t, 1)), '내일']] as const) {
    const b = planFor(st, k, t).blocks.find((x) => x.taskId === id && isAfter(x.end, t));
    if (b) return isBefore(b.start, t) || b.start.getTime() === t.getTime() ? '지금' : `${label} ${formatHm(b.start)}`;
  }
  return null;
}

const placedText = (w: string | null, fallback: string): string => (w === '지금' ? '지금 하는 조각에 이어서 해요' : w ? `${w}에 넣었어요` : fallback);

/** 할 일을 바꾼 뒤 알림: 일정이 바뀌었으면 그렇다고 말하고 되돌리기를 준다. */
export function notifyPlan(toast: ToastFn, r: PlanChange, changed: string, unchanged = changed): void {
  const base = r.replanned ? changed : unchanged;
  // 빈 시간이 모자라 밀려난 일이 있으면 숨기지 않고 알린다.
  const late = r.deferred.length ? ` · 빈 시간이 부족해 ${r.deferred.slice(0, 2).join(', ')}${r.deferred.length > 2 ? ` 외 ${r.deferred.length - 2}개` : ''}는 다음 날로 넘겼어요` : '';
  toast(base + late, 'plan');
}

export function Tasks({ s, now, toast }: { s: AppState; now: Date; toast: ToastFn }) {
  const [editing, setEditing] = useState<TaskItem | null>(null);
  const [showDone, setShowDone] = useState(false);
  const todayKey = dateKey(now);
  const tomorrowKey = dateKey(addDays(now, 1));
  const today = useMemo(() => planFor(s, todayKey, now), [s, todayKey, now]);
  const tomorrow = useMemo(() => planFor(s, tomorrowKey, now), [s, tomorrowKey, now]);
  const open = s.tasks.filter((t) => !t.done);
  const done = s.tasks.filter((t) => t.done);

  // AI 추천 순서(며칠 배운 뒤부터)
  const prefs = useMemo(() => learnPrefs(s.learning), [s.learning]);
  const suggestion = useMemo(() => (prefs ? suggestOrder(open, prefs, now) : null), [prefs, open, now]);
  const showSuggestion = !!suggestion && s.learning.dismissedDay !== todayKey;
  const learnedDays = useMemo(
    () => new Set([...s.learning.reorders.map((r) => dateKey(r.at)), ...s.learning.completions.map((c) => dateKey(c.at))]).size,
    [s.learning],
  );

  const placement = (t: TaskItem): string => {
    if (s.observation?.phase === 'recording') return '첫날 기록이 끝나면 일정에 넣어요';
    const tb = today.blocks.filter((b) => b.taskId === t.id && !isBefore(b.end, now));
    if (tb.length) return `오늘 ${formatHm(tb[0].start)}부터 ${formatDuration(tb.reduce((n, b) => n + blockMinutes(b), 0))}`;
    const past = today.blocks.filter((b) => b.taskId === t.id);
    if (past.length && !s.eveningDone.includes(todayKey)) return `오늘 ${formatHm(past[0].start)}에 잡혀 있었어요 · 저녁 확인에서 반영해요`;
    const nb = tomorrow.blocks.filter((b) => b.taskId === t.id);
    if (nb.length) return `내일 ${formatHm(nb[0].start)}부터 ${formatDuration(nb.reduce((n, b) => n + blockMinutes(b), 0))}`;
    if (tomorrow.deferred.some((x) => x.taskId === t.id)) return '빈 시간이 부족해 모레 이후로 넘겨요';
    return '모레 이후 일정에 넣어요';
  };

  return (
    <div className="screen">
      <div className="topbar">
        <h1 className="t-title">할 일</h1>
        <button type="button" className="btn primary small" onClick={() => setEditing(blankTask())}>
          <Icon name="plus" size={16} /> 추가
        </button>
      </div>
      <p className="t-label" style={{ margin: 0 }}>
        위에 있는 일부터 빈 시간에 자동으로 넣어요. 오른쪽 손잡이를 끌어 순서를 바꾸세요.
      </p>

      {showSuggestion && suggestion && (
        <section className="card ai-card" aria-label="AI 추천 순서">
          <div className="row between">
            <span className="row" style={{ gap: 8 }}>
              <span className="ai-badge">AI</span>
              <span className="t-h2">이 순서는 어때요?</span>
            </span>
            <span className="t-label">{prefs!.days}일 동안 배운 순서</span>
          </div>
          <ol className="ai-order">
            {suggestion.order.map((id, i) => {
              const t = open.find((x) => x.id === id)!;
              const from = open.findIndex((x) => x.id === id);
              return (
                <li key={id}>
                  <span className="num ai-no">{i + 1}</span>
                  <span className="grow ellipsis">{t.title}</span>
                  {from !== i && <span className={`ai-move ${from > i ? 'up' : 'down'}`}>{from > i ? `▲ ${from - i}` : `▼ ${i - from}`}</span>}
                </li>
              );
            })}
          </ol>
          {suggestion.reasons.map((r) => (
            <span key={r} className="impact">
              {r}
            </span>
          ))}
          <div className="row" style={{ gap: 8 }}>
            <button
              type="button"
              className="btn primary grow"
              onClick={() => {
                haptic(10);
                notifyPlan(toast, reorderTasks(suggestion.order, false), 'AI 추천 순서로 남은 일정을 다시 짰어요', 'AI 추천 순서로 바꿨어요');
              }}
            >
              이 순서로 바꾸기
            </button>
            <button type="button" className="btn" onClick={dismissOrderSuggestion}>
              지금 순서 유지
            </button>
          </div>
        </section>
      )}
      {!prefs && open.length >= 2 && (
        <div className="learn-bar" aria-label="AI 학습 진행">
          <span className="ai-badge">AI</span>
          <span className="grow t-label">
            우선순위를 배우는 중 · {Math.min(learnedDays, LEARN_DAYS)}/{LEARN_DAYS}일. 순서를 바꾸거나 할 일을 끝내면 배워요.
          </span>
          <span className="learn-meter">
            <i style={{ width: `${(Math.min(learnedDays, LEARN_DAYS) / LEARN_DAYS) * 100}%` }} />
          </span>
        </div>
      )}

      <section className="card list" aria-label="진행 중인 할 일">
        {open.length === 0 && <div className="empty">할 일이 없어요. 추가하면 일정에 자동으로 들어가요.</div>}
        <SortableList
          items={open}
          onReorder={(ids) => notifyPlan(toast, reorderTasks(ids), '새 순서로 남은 일정을 바로 다시 짰어요', '순서를 바꿨어요')}
          render={(t, i, handle) => {
            const { planned, remaining } = taskPlanMinutes(s, t);
            const cal = calibrationFor(s.durations, t);
            const usedUp = remaining === 0 && t.doneMinutes > 0;
            return (
            <>
            <div className="task-row">
              <span className="rank num">{i + 1}</span>
              <input
                type="checkbox"
                aria-label={`${t.title} 완료`}
                checked={false}
                onChange={() => {
                  haptic(10);
                  notifyPlan(toast, toggleTaskDone(t.id), `${t.title} 끝! 남은 일정을 다시 짰어요`, `${t.title} 끝!`);
                }}
                className="task-check"
              />
              <button type="button" className="linklike grow col" style={{ gap: 2, minWidth: 0 }} onClick={() => setEditing(t)}>
                <span className="strong ellipsis">{t.title}</span>
                <span className="t-label num">
                  {TASK_TYPE[t.type].label} · {usedUp ? `${formatDuration(planned)} 다 씀` : t.doneMinutes > 0 ? `남은 ${formatDuration(remaining)}` : formatDuration(t.estMinutes)}
                  {cal && t.doneMinutes === 0 && <span className="calib"> → 일정엔 {formatDuration(planned)}</span>}
                </span>
                <span className="t-label accent ellipsis">{usedUp ? '잡은 시간을 다 썼어요' : placement(t)}</span>
              </button>
              {handle}
            </div>
            {usedUp && (
              <div className="usedup" aria-label={`${t.title} 잡은 시간 다 씀`}>
                <span className="t-label grow">다 끝냈어요? 덜 끝났으면 시간을 늘려 다시 넣어요</span>
                <button type="button" className="btn small primary" onClick={() => notifyPlan(toast, toggleTaskDone(t.id), `${t.title} 끝! 실제 걸린 시간을 다음 예상에 반영해요`)}>
                  끝났어요
                </button>
                {[30, 60].map((m) => (
                  <button
                    key={m}
                    type="button"
                    className="btn small"
                    onClick={() => {
                      notifyPlan(toast, extendTask(t.id, m), `${formatDuration(m)} 더 · ${placedText(whereNow(t.id), '빈 시간이 생기면 넣어요')}`);
                    }}
                  >
                    +{formatDuration(m)}
                  </button>
                ))}
              </div>
            )}
            </>
            );
          }}
        />
      </section>

      {done.length > 0 && (
        <section className="col">
          <button type="button" className="btn ghost small" style={{ alignSelf: 'flex-start' }} onClick={() => setShowDone(!showDone)}>
            완료 {done.length}개 {showDone ? '접기' : '보기'}
          </button>
          {showDone && (
            <div className="card list">
              {done.map((t) => (
                <div key={t.id} className="line-row">
                  <input type="checkbox" aria-label={`${t.title} 완료 취소`} checked onChange={() => notifyPlan(toast, toggleTaskDone(t.id), `${t.title}${objectParticle(t.title)} 다시 일정에 넣었어요`, '완료를 취소했어요')} className="task-check" />
                  <span className="grow muted" style={{ textDecoration: 'line-through' }}>
                    {t.title}
                  </span>
                  <button type="button" className="icon-btn" aria-label={`${t.title} 지우기`} onClick={() => notifyPlan(toast, deleteTask(t.id), '지웠어요')}>
                    <Icon name="trash" size={18} />
                  </button>
                </div>
              ))}
            </div>
          )}
        </section>
      )}

      {editing && <TaskSheet s={s} task={editing} onClose={() => setEditing(null)} toast={toast} />}
    </div>
  );
}

// ---------------------------------------------------------------------------
// 끌어서 순서 바꾸기
// ---------------------------------------------------------------------------

interface DragState {
  id: string;
  from: number;
  to: number;
  startY: number;
  dy: number;
  heights: number[];
  mids: number[];
}

function SortableList<T extends { id: string; title: string }>({
  items,
  onReorder,
  render,
}: {
  items: T[];
  onReorder: (ids: string[]) => void;
  render: (item: T, index: number, handle: ReactNode) => ReactNode;
}) {
  const refs = useRef<(HTMLDivElement | null)[]>([]);
  const [drag, setDrag] = useState<DragState | null>(null);

  const move = (from: number, to: number) => {
    if (from === to) return;
    const ids = items.map((x) => x.id);
    const [m] = ids.splice(from, 1);
    ids.splice(to, 0, m);
    onReorder(ids);
  };

  const start = (e: React.PointerEvent, i: number) => {
    e.preventDefault();
    e.stopPropagation();
    const rects = refs.current.slice(0, items.length).map((el) => el!.getBoundingClientRect());
    (e.currentTarget as Element).setPointerCapture(e.pointerId);
    haptic(12);
    setDrag({ id: items[i].id, from: i, to: i, startY: e.clientY, dy: 0, heights: rects.map((r) => r.height), mids: rects.map((r) => r.top + r.height / 2) });
  };
  const moveTo = (e: React.PointerEvent) => {
    if (!drag) return;
    const dy = e.clientY - drag.startY;
    const center = drag.mids[drag.from] + dy;
    let to = 0;
    drag.mids.forEach((m, j) => {
      if (j !== drag.from && center > m) to++;
    });
    if (to !== drag.to) haptic(5);
    setDrag({ ...drag, dy, to });
  };
  const end = () => {
    if (!drag) return;
    const { from, to } = drag;
    setDrag(null);
    move(from, to);
  };

  const shift = (i: number): number => {
    if (!drag || i === drag.from) return 0;
    const h = drag.heights[drag.from];
    if (drag.from < drag.to && i > drag.from && i <= drag.to) return -h;
    if (drag.to < drag.from && i >= drag.to && i < drag.from) return h;
    return 0;
  };

  return (
    <div className="sortable">
      {items.map((it, i) => {
        const dragging = drag?.from === i;
        const handle = (
          <button
            type="button"
            className="drag-handle no-swipe"
            aria-label={`${it.title} 순서 바꾸기, 위아래 화살표로 이동`}
            onPointerDown={(e) => start(e, i)}
            onPointerMove={moveTo}
            onPointerUp={end}
            onPointerCancel={end}
            onKeyDown={(e) => {
              if (e.key === 'ArrowUp' && i > 0) {
                e.preventDefault();
                move(i, i - 1);
              }
              if (e.key === 'ArrowDown' && i < items.length - 1) {
                e.preventDefault();
                move(i, i + 1);
              }
            }}
          >
            <svg width="20" height="20" viewBox="0 0 24 24" aria-hidden="true">
              <path d="M5 8h14M5 12h14M5 16h14" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
            </svg>
          </button>
        );
        return (
          <div
            key={it.id}
            ref={(el) => {
              refs.current[i] = el;
            }}
            className={`sort-item ${dragging ? 'dragging' : ''}`}
            style={{ transform: dragging ? `translateY(${drag!.dy}px) scale(1.02)` : `translateY(${shift(i)}px)` }}
          >
            {render(it, i, handle)}
          </div>
        );
      })}
    </div>
  );
}

// ---------------------------------------------------------------------------
// 할 일 추가·고치기: 이름, 종류, 걸리는 시간만
// ---------------------------------------------------------------------------

function blankTask(): TaskItem {
  const t = clockNow();
  return { id: '', title: '', estMinutes: TASK_TYPE.work.defaultMinutes, dueAt: addDays(t, 30), type: 'work', priority: 'normal', focus: true, doneMinutes: 0, createdAt: t };
}

const QUICK_MINUTES = [15, 30, 60, 90, 120, 180];

function TaskSheet({ s, task, onClose, toast }: { s: AppState; task: TaskItem; onClose: () => void; toast: ToastFn }) {
  const [t, setT] = useState<TaskItem>(task);
  const [minutesTouched, setMinutesTouched] = useState(!!task.id);
  const up = (p: Partial<TaskItem>) => setT((x) => ({ ...x, ...p }));
  const cal = calibrationFor(s.durations, t);
  const planned = taskPlanMinutes(s, t).planned;
  const save = () => {
    haptic(10);
    const id = t.id || newId('task');
    const title = t.title.trim();
    const r = saveTask({ ...t, title, id, focus: focusByType(t.type), createdAt: t.createdAt ?? clockNow() });
    const w = whereNow(id);
    notifyPlan(toast, r, `${title} · ${placedText(w, '일정을 다시 짰어요')}`, task.id ? '저장했어요' : `${title} · ${placedText(w, '빈 시간이 생기면 자동으로 넣어요')}`);
    onClose();
  };
  return (
    <Sheet title={task.id ? '할 일 고치기' : '할 일 추가'} onClose={onClose}>
      <label className="field">
        <span>업무 이름</span>
        <input
          className="input big-input"
          value={t.title}
          onChange={(e) => up({ title: e.target.value })}
          onKeyDown={(e) => e.key === 'Enter' && t.title.trim() && save()}
          placeholder="예: 분기 보고서 작성"
          autoFocus
        />
      </label>
      <div className="field">
        <span>업무 종류</span>
        <div className="chips" role="radiogroup" aria-label="업무 종류">
          {(Object.keys(TASK_TYPE) as TaskType[]).map((k) => (
            <button
              key={k}
              type="button"
              className="chip"
              role="radio"
              aria-checked={t.type === k}
              onClick={() => up({ type: k, ...(minutesTouched ? {} : { estMinutes: TASK_TYPE[k].defaultMinutes }) })}
            >
              {TASK_TYPE[k].label}
            </button>
          ))}
        </div>
      </div>
      <div className="field">
        <span>걸리는 시간 · 모르면 종류별 기본값</span>
        <div className="chips" role="radiogroup" aria-label="걸리는 시간">
          {QUICK_MINUTES.map((m) => (
            <button
              key={m}
              type="button"
              className="chip"
              role="radio"
              aria-checked={t.estMinutes === m}
              onClick={() => {
                setMinutesTouched(true);
                up({ estMinutes: m });
              }}
            >
              {formatDuration(m)}
            </button>
          ))}
        </div>
        <div className="row" style={{ gap: 8 }}>
          <input
            className="input num"
            type="number"
            inputMode="numeric"
            aria-label="직접 입력(분)"
            min={5}
            step={5}
            value={t.estMinutes}
            onChange={(e) => {
              setMinutesTouched(true);
              up({ estMinutes: Math.max(5, Number(e.target.value) || 5) });
            }}
            style={{ width: 110 }}
          />
          <span className="t-label">분 · 50분씩 나눠 빈 시간에 넣어요</span>
        </div>
        {cal && (
          <p className="impact" style={{ margin: 0 }}>
            {calibrationText(t, cal, TASK_TYPE[t.type].label)} · 일정에는 {formatDuration(planned)} 잡아요
          </p>
        )}
      </div>
      {t.doneMinutes > 0 && <p className="t-label" style={{ margin: 0 }}>지금까지 {formatDuration(t.doneMinutes)} 했어요</p>}
      <div className="row" style={{ gap: 8 }}>
        {task.id && (
          <button
            type="button"
            className="btn danger"
            onClick={() => {
              notifyPlan(toast, deleteTask(task.id), '지웠어요. 남은 일정을 다시 짰어요', '지웠어요');
              onClose();
            }}
          >
            지우기
          </button>
        )}
        <button type="button" className="btn primary grow" disabled={!t.title.trim()} onClick={save}>
          저장
        </button>
      </div>
    </Sheet>
  );
}
