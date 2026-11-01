import { emptyLearning, learnPrefs, snapshot, suggestOrder } from '../priorityModel';
import type { TaskItem, TaskType } from '../../engine/models';

const at = (day: number, h = 9) => new Date(2026, 9, day, h);
const task = (id: string, type: TaskType, est: number): TaskItem => ({
  id, title: id, type, estMinutes: est, dueAt: at(30), priority: 'normal', focus: false, doneMinutes: 0, createdAt: at(15),
});

test('3일이 모이기 전에는 추천하지 않는다', () => {
  const log = emptyLearning();
  log.reorders.push(snapshot([task('a', 'personal', 10), task('b', 'work', 120)], at(18)));
  log.reorders.push(snapshot([task('a', 'personal', 10), task('b', 'work', 120)], at(19)));
  expect(learnPrefs(log)).toBeNull();
});

test('짧은 일·개인 일을 먼저 두는 습관을 배워 순서를 제안한다', () => {
  const log = emptyLearning();
  for (const d of [16, 17, 18, 19]) {
    log.reorders.push(snapshot([task('p', 'personal', 15), task('h', 'homework', 60), task('w', 'work', 180)], at(d)));
  }
  const prefs = learnPrefs(log)!;
  expect(prefs.days).toBe(4);
  expect(prefs.typePref.personal).toBeLessThan(prefs.typePref.work);
  expect(prefs.lenSlope).toBeGreaterThan(0.2);
  const current = [task('report', 'work', 180), task('english', 'homework', 60), task('call', 'personal', 10)];
  const s = suggestOrder(current, prefs, at(20))!;
  expect(s.order).toEqual(['call', 'english', 'report']);
  expect(s.reasons.join(' ')).toContain('짧은 일을 먼저');
  expect(s.moved).toBe(2);
});

test('이미 배운 순서와 같으면 제안하지 않는다', () => {
  const log = emptyLearning();
  for (const d of [16, 17, 18]) log.reorders.push(snapshot([task('p', 'personal', 15), task('h', 'homework', 60), task('w', 'work', 180)], at(d)));
  const prefs = learnPrefs(log)!;
  expect(suggestOrder([task('a', 'personal', 10), task('b', 'homework', 50), task('c', 'work', 200)], prefs, at(20))).toBeNull();
});
