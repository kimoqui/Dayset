// 1순위 '자동': 순서 바로 반영, 걸리는 시간 자동 보정, 캘린더 가져오기. 웹 __tests__/auto.test.ts를 옮겼다.
// 순수 .ics 읽기 테스트는 ics_test.dart에 있다. 웹의 calendarSync(checkIcs·syncGoogle)는 앱에 아직 없어 옮기지 않았다.
// 시각은 한국 시간 기준이다(TZ=Asia/Seoul로 실행). .ics 수업 시각이 Asia/Seoul이라 다른 시간대에서는 '오늘 9시 수업' 검사가 맞지 않는다.

import 'package:dayset/app/duration.dart';
import 'package:dayset/app/ics.dart';
import 'package:dayset/app/state.dart';
import 'package:dayset/app/store.dart';
import 'package:dayset/core/model/models.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime at(int day, int h, [int m = 0]) => DateTime(2026, 10, day, h, m);

TaskItem task(String id, String title, int est, [TaskType type = TaskType.work]) =>
    TaskItem(id: id, title: title, estMinutes: est, dueAt: at(30, 18), type: type, focus: type == TaskType.work, createdAt: at(19, 6));

late Store store;
late DateTime wall;

void goTo(DateTime d) => store.setFixedClock(d);

ScheduleBlock? firstTaskBlock() => store.state.plans['2026-10-19']!.blocks.where((b) => b.kind == BlockKind.task).firstOrNull;
List<ScheduleBlock> taskBlocks() => store.state.plans['2026-10-19']!.blocks.where((b) => b.kind == BlockKind.task).toList();
int minutesOf(Iterable<ScheduleBlock> bs) => bs.fold(0, (n, x) => n + x.end.difference(x.start).inMinutes);

DurationLearning durs(List<(String, TaskType, int, int)> xs) => DurationLearning(samples: [
      for (final (i, x) in xs.indexed) DurationSample(at: at(10 + i, 20), type: x.$2, title: x.$1, est: x.$3, actual: x.$4),
    ]);

const ics = 'BEGIN:VCALENDAR\r\n'
    'VERSION:2.0\r\n'
    'X-WR-CALNAME:내 캘린더\r\n'
    'BEGIN:VEVENT\r\n'
    'UID:once@x\r\n'
    'DTSTART;TZID=Asia/Seoul:20261020T100000\r\n'
    'DTEND;TZID=Asia/Seoul:20261020T113000\r\n'
    'SUMMARY:팀 회의\\, 주간\r\n'
    'END:VEVENT\r\n'
    'BEGIN:VEVENT\r\n'
    'UID:class@x\r\n'
    'DTSTART;TZID=Asia/Seoul:20261005T090000\r\n'
    'DTEND;TZID=Asia/Seoul:20261005T103000\r\n'
    'RRULE:FREQ=WEEKLY;BYDAY=MO,WE;UNTIL=20261130T000000Z\r\n'
    'EXDATE;TZID=Asia/Seoul:20261021T090000\r\n'
    'SUMMARY:경영학원론\r\n'
    'END:VEVENT\r\n'
    'BEGIN:VEVENT\r\n'
    'UID:daily@x\r\n'
    'DTSTART;TZID=Asia/Seoul:20261019T070000\r\n'
    'DTEND;TZID=Asia/Seoul:20261019T073000\r\n'
    'RRULE:FREQ=DAILY;COUNT=3\r\n'
    'SUMMARY:아침 스터디\r\n'
    'END:VEVENT\r\n'
    'END:VCALENDAR\r\n';

void main() {
  setUp(() {
    wall = DateTime(2026, 10, 19, 6);
    store = Store(storage: StateStorage(MemoryStore()), wallClock: () => wall);
    goTo(at(19, 6, 0));
    store.completeOnboarding(goals: defaultGoals, settings: const PersonalSettings(travelMinutes: 0), usualWake: 7 * 60);
  });

  group('순서 바로 반영', () {
    test('할 일을 넣거나 순서를 바꾸면 오늘 일정을 바로 다시 짜고, 되돌릴 수 있다', () {
      goTo(at(19, 6, 30));
      final r1 = store.saveTask(task('a', '보고서', 60));
      expect(r1.replanned, isTrue);
      store.saveTask(task('b', '메일 정리', 30));
      expect(firstTaskBlock()?.taskId, 'a');
      expect(store.state.plans['2026-10-19']!.inputsVersion, store.state.inputsVersion); // '다시 짜기' 안내가 뜨지 않는다

      final r = store.reorderTasks(['b', 'a']);
      expect(r.replanned, isTrue);
      expect(firstTaskBlock()?.taskId, 'b');

      expect(store.canUndoPlan(), isTrue);
      expect(store.undoPlanChange(), isTrue);
      expect(store.state.tasks.map((t) => t.id).toList(), ['a', 'b']);
      expect(firstTaskBlock()?.taskId, 'a');
    });

    test('되돌리기는 15초 안에만 된다', () {
      goTo(at(19, 6, 30));
      store.saveTask(task('a', '보고서', 60));
      wall = wall.add(const Duration(seconds: 14));
      expect(store.canUndoPlan(), isTrue);
      wall = wall.add(const Duration(seconds: 2));
      expect(store.canUndoPlan(), isFalse);
      expect(store.undoPlanChange(), isFalse);
      expect(store.state.tasks, hasLength(1));
    });

    test('이미 지난 조각은 그대로 두고 남은 시간만 바꾼다', () {
      goTo(at(19, 9, 0));
      store.saveTask(task('a', '보고서', 60));
      store.saveTask(task('b', '메일 정리', 30));
      final before = taskBlocks();
      goTo(before[0].end.add(const Duration(minutes: 1)));
      store.reorderTasks(['b', 'a']);
      expect(taskBlocks()[0].id, before[0].id); // 지난 조각 유지
    });

    test('지금 하고 있는 조각은 끊지 않고, 그 뒤부터 새 순서로 짠다', () {
      goTo(at(19, 6, 30));
      store.saveTask(task('a', '보고서', 120));
      store.saveTask(task('b', '메일 정리', 30));
      final cur = firstTaskBlock()!;
      goTo(cur.start.add(const Duration(minutes: 20))); // 'a' 하는 중
      final r = store.reorderTasks(['b', 'a']);
      final blocks = taskBlocks();
      expect(blocks.any((b) => b.id == cur.id), isTrue); // 진행 중인 조각 유지
      final next = blocks.where((b) => !b.start.isBefore(cur.end)).toList();
      expect(next[0].taskId, 'b'); // 그 뒤는 새 순서
      expect(r.replanned, isTrue);
      // 하던 일을 끝내면 그 조각은 지금에서 끊는다
      store.toggleTaskDone('a');
      expect(store.state.plans['2026-10-19']!.blocks.any((b) => b.id == cur.id), isFalse);
    });

    test('빈 시간이 모자라 밀려난 할 일을 알려 준다', () {
      goTo(at(19, 6, 30));
      final r = store.saveTask(task('big', '대형 프로젝트', 900));
      expect(r.deferred, contains('대형 프로젝트'));
    });

    test('첫날 기록 중에는 일정을 짜지 않는다', () {
      store.resetAll();
      goTo(at(19, 6, 0));
      store.startObservation();
      final r = store.saveTask(task('a', '보고서', 60));
      expect(r.replanned, isFalse);
    });
  });

  group('걸리는 시간 자동 보정', () {
    test('같은 종류 3건부터 실제/예상 중앙값으로 보정한다', () {
      final two = durs([('영어', TaskType.homework, 60, 80), ('수학', TaskType.homework, 40, 52)]);
      expect(calibrationFor(two, type: TaskType.homework, title: '국어'), isNull);
      final three = durs([('영어', TaskType.homework, 60, 80), ('수학', TaskType.homework, 40, 52), ('과학', TaskType.homework, 30, 40)]);
      final c = calibrationFor(three, type: TaskType.homework, title: '국어')!;
      expect(c.basis, CalibrationBasis.type);
      expect(c.ratio, closeTo(1.3, 0.005));
      expect(plannedMinutes(task('x', '국어', 60, TaskType.homework), three), 80);
      expect(calibrationText('국어', c, '숙제'), '숙제는 보통 예상보다 1.3배 걸렸어요');
    });

    test('같은 이름이 2건 있으면 이름 기준이 먼저다', () {
      final s = durs([
        ('영어 숙제 1', TaskType.homework, 60, 90),
        ('영어숙제2', TaskType.homework, 60, 90),
        ('수학', TaskType.homework, 60, 60),
        ('과학', TaskType.homework, 60, 60),
        ('사회', TaskType.homework, 60, 60),
      ]);
      expect(normTitle('영어 숙제 3'), '영어숙제');
      final c = calibrationFor(s, type: TaskType.homework, title: '영어 숙제')!;
      expect(c.basis, CalibrationBasis.title);
      expect(c.ratio, 1.5);
      expect(calibrationFor(s, type: TaskType.homework, title: '국어'), isNull); // 종류 중앙값 1.0 → 보정 안 함
    });

    test('비율은 0.5~2배로 묶고, 끄면 보정하지 않는다', () {
      final s = durs([('a', TaskType.work, 10, 100), ('b', TaskType.work, 10, 100), ('c', TaskType.work, 10, 100)]);
      expect(calibrationFor(s, type: TaskType.work, title: 'z')!.ratio, 2);
      expect(calibrationFor(s.copyWith(on: false), type: TaskType.work, title: 'z'), isNull);
    });

    test('끝낼 때 오늘 지난 조각만큼을 실제 시간으로 남기고, 일정에 반영한다', () {
      goTo(at(19, 9, 0));
      store.saveTask(task('a', '보고서', 60));
      final b = firstTaskBlock()!;
      goTo(b.start.add(const Duration(minutes: 40))); // 40분 만에 끝냄
      store.toggleTaskDone('a');
      final smp = store.state.durations.samples;
      expect(smp, hasLength(1));
      expect([smp[0].est, smp[0].actual, smp[0].taskId], [60, 40, 'a']);
      // 완료를 취소하면 기록도 지운다
      store.toggleTaskDone('a');
      expect(store.state.durations.samples, hasLength(0));
    });

    test('일정 밖에서 끝내면 실제 시간을 모르니 남기지 않는다', () {
      goTo(at(19, 9, 0));
      store.saveTask(task('a', '보고서', 60));
      store.toggleTaskDone('a');
      expect(store.state.durations.samples, hasLength(0));
    });

    test('잡은 시간을 다 써도 자동 완료하지 않고, 늘리면 다시 배치한다', () {
      goTo(at(19, 9, 0));
      store.saveTask(task('a', '메일', 30));
      final b = firstTaskBlock()!;
      goTo(b.end.add(const Duration(minutes: 1)));
      store.markDid('2026-10-19', b);
      final t = store.state.tasks[0];
      expect(t.done, isFalse);
      expect(store.taskPlanMinutes(t).remaining, 0);
      store.extendTask('a', 30);
      final t2 = store.state.tasks[0];
      final pm = store.taskPlanMinutes(t2);
      expect([pm.planned, pm.remaining], [60, 30]);
      final later = store.state.plans['2026-10-19']!.blocks.where((x) => x.kind == BlockKind.task && x.taskId == 'a' && x.start.isAfter(b.end)).toList();
      expect(minutesOf(later), 30);
      // 다 끝내면 실제 60분(30 + 30)으로 남는다
      goTo(later[0].end.add(const Duration(minutes: 1)));
      store.toggleTaskDone('a');
      final s0 = store.state.durations.samples[0];
      expect([s0.est, s0.actual], [30, 60]);
    });

    test('보정이 쌓이면 새 할 일을 더 길게 잡는다', () {
      goTo(at(19, 9, 0));
      store.replaceState(store.state.copyWith(
          durations: durs([('a', TaskType.homework, 60, 90), ('b', TaskType.homework, 60, 90), ('c', TaskType.homework, 60, 90)])));
      store.saveTask(task('h', '영어', 60, TaskType.homework));
      expect(minutesOf(store.state.plans['2026-10-19']!.blocks.where((x) => x.taskId == 'h')), 90);
    });
  });

  group('.ics 가져오기', () {
    final from = DateTime(2026, 10, 19);
    final to = DateTime(2026, 11, 2);

    test('가져오면 그 캘린더 일정을 통째로 바꾸고, 일정을 다시 짠다', () {
      goTo(at(19, 6, 30));
      final one = parseIcs(ics, from, to).events;
      final res = store.importCalendar(one, id: 'ics-file', kind: CalendarKind.ics, name: '내 캘린더');
      expect(res.count, one.length);
      expect(store.state.events.where((e) => e.source == 'ics-file'), hasLength(one.length));
      store.saveEvent(FixedEvent(id: 'mine', title: '직접 넣은 일정', start: at(23, 15), end: at(23, 16)));
      // 다시 가져오면 직접 넣은 일정은 남기고 가져온 것만 바꾼다
      store.importCalendar(one.take(2).toList(), id: 'ics-file', kind: CalendarKind.ics, name: '내 캘린더');
      final ev = store.state.events;
      expect(ev.where((e) => e.source == 'ics-file'), hasLength(2));
      expect(ev.any((e) => e.id == 'mine'), isTrue);
      expect([store.state.calendars[0].id, store.state.calendars[0].count], ['ics-file', 2]);
      // 오늘 9시 수업이 일정에 들어간다
      expect(store.state.plans['2026-10-19']!.blocks.any((b) => b.title == '경영학원론'), isTrue);
      store.removeCalendar('ics-file');
      expect(store.state.events.map((e) => e.id).toList(), ['mine']);
      expect(store.state.calendars, hasLength(0));
    });
  });

  group('비정상 상황', () {
    test('5분 안 된 기록은 남기지 않고, 1/3~3배를 벗어나면 보정에서 뺀다', () {
      DurationSample smp(String title, int est, int actual) => DurationSample(at: at(19, 9), type: TaskType.work, title: title, est: est, actual: actual);
      var d = const DurationLearning();
      d = addSample(d, smp('a', 60, 3));
      expect(d.samples, hasLength(0));
      d = addSample(d, smp('a', 30, 600)); // 며칠 묵힘
      expect(d.samples[0].outlier, isTrue);
      d = addSample(d, smp('b', 60, 90));
      d = addSample(d, smp('c', 60, 90));
      expect(calibrationFor(d, type: TaskType.work, title: 'z'), isNull); // 정상 2건뿐
      d = addSample(d, smp('d', 60, 90));
      expect(calibrationFor(d, type: TaskType.work, title: 'z')!.ratio, 1.5);
    });

    test('직접 넣은 일정과 같은 일정은 가져오지 않는다(중복)', () {
      goTo(at(19, 6, 30));
      store.saveEvent(FixedEvent(id: 'm', title: '팀 회의', start: at(20, 10), end: at(20, 11)));
      final r = store.importCalendar([
        ImportedEvent(uid: '1', title: '팀  회의', start: at(20, 10), end: at(20, 11)),
        ImportedEvent(uid: '2', title: '수업', start: at(20, 13), end: at(20, 14)),
      ], id: 'g', kind: CalendarKind.ics, name: 'x');
      expect([r.count, r.dupes], [1, 1]);
    });

    test('너무 많은 일정은 잘라서 저장 공간을 지킨다', () {
      goTo(at(19, 6, 30));
      final base = at(20, 0);
      final many = [
        for (var i = 0; i < maxImport + 50; i++)
          ImportedEvent(uid: 'u$i', title: 'e$i', start: base.add(Duration(minutes: i)), end: base.add(Duration(minutes: i, seconds: 30))),
      ];
      final r = store.importCalendar(many, id: 'g', kind: CalendarKind.ics, name: 'x');
      expect([r.count, r.capped], [maxImport, 50]);
    });

    test('동기화가 실패해도 이전에 가져온 일정은 그대로 두고 다시 연결을 표시한다', () {
      goTo(at(19, 6, 30));
      store.importCalendar([ImportedEvent(uid: '1', title: '회의', start: at(20, 10), end: at(20, 11))], id: 'google', kind: CalendarKind.google, name: '구글');
      store.markCalendarError('google', '연결이 만료됐어요', needsAuth: true);
      final g = store.state.calendars.firstWhere((c) => c.id == 'google');
      expect(g.needsAuth, isTrue);
      expect(g.error, '연결이 만료됐어요');
      expect(store.state.events.where((e) => e.source == 'google'), hasLength(1));
    });
  });
}
