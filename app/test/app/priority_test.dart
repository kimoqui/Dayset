// 우선순위 학습. 웹 __tests__/priority.test.ts를 옮겼다.

import 'package:dayset/app/priority_model.dart';
import 'package:dayset/app/state.dart';
import 'package:dayset/core/model/models.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime at(int day, [int h = 9]) => DateTime(2026, 10, day, h);
TaskItem task(String id, TaskType type, int est) => TaskItem(id: id, title: id, type: type, estMinutes: est, dueAt: at(30), createdAt: at(15));

LearningLog withReorders(List<Reorder> rs) => LearningLog(reorders: rs);

void main() {
  test('3일이 모이기 전에는 추천하지 않는다', () {
    final log = withReorders([
      snapshot([task('a', TaskType.personal, 10), task('b', TaskType.work, 120)], at(18)),
      snapshot([task('a', TaskType.personal, 10), task('b', TaskType.work, 120)], at(19)),
    ]);
    expect(learnPrefs(log), isNull);
  });

  test('짧은 일·개인 일을 먼저 두는 습관을 배워 순서를 제안한다', () {
    final log = withReorders([
      for (final d in [16, 17, 18, 19]) snapshot([task('p', TaskType.personal, 15), task('h', TaskType.homework, 60), task('w', TaskType.work, 180)], at(d)),
    ]);
    final prefs = learnPrefs(log)!;
    expect(prefs.days, 4);
    expect(prefs.typePref[TaskType.personal]!, lessThan(prefs.typePref[TaskType.work]!));
    expect(prefs.lenSlope, greaterThan(0.2));
    final current = [task('report', TaskType.work, 180), task('english', TaskType.homework, 60), task('call', TaskType.personal, 10)];
    final s = suggestOrder(current, prefs, at(20))!;
    expect(s.order, ['call', 'english', 'report']);
    expect(s.reasons.join(' '), contains('짧은 일을 먼저'));
    expect(s.moved, 2);
  });

  test('이미 배운 순서와 같으면 제안하지 않는다', () {
    final log = withReorders([
      for (final d in [16, 17, 18]) snapshot([task('p', TaskType.personal, 15), task('h', TaskType.homework, 60), task('w', TaskType.work, 180)], at(d)),
    ]);
    final prefs = learnPrefs(log)!;
    expect(suggestOrder([task('a', TaskType.personal, 10), task('b', TaskType.homework, 50), task('c', TaskType.work, 200)], prefs, at(20)), isNull);
  });
}
