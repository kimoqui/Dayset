import { useMemo, useState } from 'react';
import {
  ACTIVITY_LABEL,
  addDays,
  blockMinutes,
  dateKey,
  formatDuration,
  formatHm,
  isAfter,
  isEstimate,
  MISS_LABEL,
  MISS_REASONS,
  SOURCE_LABEL,
} from '../../engine/models';
import { evaluate, eveningAsk, logsAround, planFor } from '../../app/derive';
import { clearAnswer, extendTask, finishEvening, markDid, markMissed, markRestAsPlanned, markSkipped, setRestDay, taskPlanMinutes, toggleTaskDone } from '../../app/store';
import type { AppState } from '../../app/state';
import { Icon, Switch, TopBar } from '../kit';

export function Evening({ s, now, onBack }: { s: AppState; now: Date; onBack: () => void }) {
  const key = dateKey(now);
  const view = useMemo(() => evaluate(s, key, now), [s, key, now]);
  const tomorrow = useMemo(() => planFor(s, dateKey(addDays(now, 1)), now), [s, now]);
  const done = s.eveningDone.includes(key);
  const [missOpen, setMissOpen] = useState<string | null>(null);

  const logs = logsAround(s, key)
    .filter((l) => !isEstimate(l) && l.source !== 'evening' && (l.end == null || isAfter(l.end, new Date(now.getFullYear(), now.getMonth(), now.getDate()))))
    .sort((a, b) => a.start.getTime() - b.start.getTime());

  const missed = new Map(s.misses.filter((m) => m.day === key).map((m) => [m.blockId, m.reason]));
  const skipped = new Set(s.skips.filter((m) => m.day === key).map((m) => m.blockId));
  const didIds = new Set(s.logs.filter((l) => l.source === 'evening').map((l) => l.id.replace(/^ev-/, '')));

  // 물어볼 블록: 시작한 지 지난 습관·할 일 중 기록으로 달성이 확인되지 않은 것 + 이미 답한 것
  const { blocks: asked, open } = useMemo(() => eveningAsk(s, key, now), [s, key, now]);

  const firstEvent = tomorrow.blocks.find((b) => b.kind === 'fixed' && b.locked);

  return (
    <div className="screen plain">
      <TopBar
        title="오늘 하루 확인"
        sub="일정대로 했으면 한 번에, 다르게 한 것만 고쳐요"
        onBack={onBack}
        right={<span className="pill" style={{ whiteSpace: 'nowrap' }}>{view.isSetDay ? '셋 데이' : `습관 ${view.achieved}/${view.total}`}</span>}
      />

      <section className="card list" aria-label="자동으로 기록된 것">
        {logs.length === 0 && <div className="empty">오늘 자동으로 기록된 것이 없어요</div>}
        {logs.map((l) => (
          <div key={l.id} className="line-row">
            <span style={{ width: 22, height: 22, borderRadius: 11, background: 'var(--tint)', color: 'var(--accent)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
              <Icon name="check" size={13} stroke={3} />
            </span>
            <span className="grow">{ACTIVITY_LABEL[l.activity]}</span>
            <span className="t-body num">
              {formatHm(l.start)}
              {l.end ? `–${formatHm(l.end)}` : ' 부터'}
            </span>
            <span className="t-label" style={{ width: 32, textAlign: 'right' }}>
              {SOURCE_LABEL[l.source]}
            </span>
          </div>
        ))}
      </section>

      {open.length > 0 && (
        <section className="card tint" aria-label="한 번에 확인">
          <span className="t-body">
            기록이 없는 일정 <strong>{open.length}개</strong>가 있어요. 일정대로 했으면 한 번에 채우고, 다르게 한 것만 아래에서 고쳐요.
          </span>
          <button type="button" className="btn primary block" onClick={() => markRestAsPlanned(key)}>
            남은 {open.length}개는 일정대로 했어요
          </button>
        </section>
      )}

      {asked.length === 0 ? (
        <div className="card">
          <span className="t-body">기록이 없는 일정이 없어요. 오늘은 모두 자동으로 기록됐어요.</span>
        </div>
      ) : (
        asked.map((b) => {
          const reason = missed.get(b.id);
          const state = didIds.has(b.id) ? 'did' : reason ? 'missed' : skipped.has(b.id) ? 'skip' : missOpen === b.id ? 'asking' : 'open';
          return (
            <section key={b.id} className="card" aria-label={`${b.title} 확인`}>
              <span className="t-body" style={{ fontSize: 15 }}>
                <strong>
                  {b.title} {formatHm(b.start)}
                </strong>{' '}
                · {state === 'did' ? '했어요' : state === 'skip' ? '쉬는 날' : state === 'missed' ? '못 했어요' : '기록이 없어요'}
              </span>
              {(state === 'open' || state === 'asking') && (
                <div className="row" style={{ gap: 8 }}>
                  <button type="button" className="btn primary square grow" onClick={() => markDid(key, b)}>
                    했어요
                  </button>
                  <button type="button" className="btn square grow" aria-expanded={state === 'asking'} onClick={() => setMissOpen(state === 'asking' ? null : b.id)}>
                    못 했어요
                  </button>
                  <button type="button" className="btn square grow" onClick={() => markSkipped(key, b)}>
                    쉬는 날
                  </button>
                </div>
              )}
              {(state === 'asking' || state === 'missed') && (
                <>
                  <span className="t-label">이유를 고르면 다음 일정에 반영해요</span>
                  <div className="chips" role="radiogroup" aria-label="못 한 이유">
                    {MISS_REASONS.map((r) => (
                      <button
                        key={r}
                        type="button"
                        className="chip"
                        role="radio"
                        aria-checked={reason === r}
                        onClick={() => {
                          markMissed(key, b, r);
                          setMissOpen(null);
                        }}
                      >
                        {MISS_LABEL[r]}
                      </button>
                    ))}
                  </div>
                </>
              )}
              {state === 'did' && (
                <div className="row between">
                  <span className="t-body accent strong">
                    {b.kind === 'task' ? `${b.title} ${formatDuration(blockMinutes(b))}을 반영했어요` : `${ACTIVITY_LABEL[b.activity!]} ${formatDuration(blockMinutes(b))}을 기록했어요`}
                  </span>
                  <button type="button" className="btn ghost small" onClick={() => clearAnswer(key, b)}>
                    바꾸기
                  </button>
                </div>
              )}
              {state === 'did' && b.kind === 'task' && <TaskFinishAsk s={s} taskId={b.taskId} />}
              {state === 'skip' && (
                <div className="row between">
                  <span className="t-body muted">쉬는 날로 기록했어요. 달성률에서 빼요.</span>
                  <button type="button" className="btn ghost small" onClick={() => clearAnswer(key, b)}>
                    바꾸기
                  </button>
                </div>
              )}
              {state === 'missed' && (
                <button type="button" className="btn ghost small" style={{ alignSelf: 'flex-start' }} onClick={() => clearAnswer(key, b)}>
                  다시 고르기
                </button>
              )}
            </section>
          );
        })
      )}

      <div className="card" style={{ padding: '4px 18px' }}>
        <Switch checked={s.restDays.includes(key)} onChange={(v) => setRestDay(key, v)} label="오늘은 쉬는 날" sub="셋 데이 판정에서 빼요" onText="쉬는 날" offText="아니요" />
      </div>

      <section className="card tint" aria-label="내일">
        <span className="t-label">내일</span>
        <div className="col" style={{ gap: 4 }}>
          <div className="row between t-body">
            <span>기상 알람</span>
            <span className="strong num">{formatHm(tomorrow.wake)}</span>
          </div>
          <span className="t-label">{tomorrow.alarms[0].reason}</span>
          <div className="row between t-body">
            <span>오늘 밤 취침</span>
            <span className="strong num">{formatHm(tomorrow.bedTonight)}</span>
          </div>
          {firstEvent && (
            <div className="row between t-body">
              <span>첫 일정</span>
              <span className="num">
                {formatHm(firstEvent.start)} {firstEvent.title}
              </span>
            </div>
          )}
          <div className="row between t-body">
            <span>할 일</span>
            <span className="num">{formatDuration(tomorrow.taskMinutes)}</span>
          </div>
          {tomorrow.notes.map((n) => (
            <span key={n} className="t-label">
              {n}
            </span>
          ))}
        </div>
        {done ? (
          <p className="t-body accent strong" style={{ margin: 0 }}>
            내일 일정을 확정했어요. 기상 알람 {formatHm(tomorrow.wake)}.
          </p>
        ) : (
          <button
            type="button"
            className="btn primary block"
            onClick={() => {
              finishEvening(key);
            }}
          >
            확인 끝 · 내일 일정 확정
          </button>
        )}
      </section>
    </div>
  );
}

/** 잡은 시간을 다 쓴 할 일: 다 끝냈는지, 시간이 더 필요한지 묻는다(걸리는 시간 보정에 쓴다). */
function TaskFinishAsk({ s, taskId }: { s: AppState; taskId?: string }) {
  const t = s.tasks.find((x) => x.id === taskId);
  if (!t || t.done || taskPlanMinutes(s, t).remaining > 0) return null;
  return (
    <div className="usedup" aria-label={`${t.title} 다 끝났는지`}>
      <span className="t-label grow">{t.title}에 잡은 시간을 다 썼어요. 다 끝냈어요?</span>
      <button type="button" className="btn small primary" onClick={() => toggleTaskDone(t.id)}>
        끝났어요
      </button>
      <button type="button" className="btn small" onClick={() => extendTask(t.id, 30)}>
        +30분
      </button>
      <button type="button" className="btn small" onClick={() => extendTask(t.id, 60)}>
        +1시간
      </button>
    </div>
  );
}
