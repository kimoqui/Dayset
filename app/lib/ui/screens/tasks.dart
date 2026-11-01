// 할 일 탭. 웹 버전 src/ui/screens/Tasks.tsx와 같은 흐름이다.
// 위에 있는 일부터 빈 시간에 자동으로 넣는다. 손잡이를 끌어 순서를 바꾸면 남은 일정을 바로 다시 짠다(되돌리기 15초).

import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/derive.dart';
import '../../app/duration.dart';
import '../../app/priority_model.dart';
import '../../app/state.dart';
import '../../app/store.dart';
import '../../core/engine/coaching.dart';
import '../../core/model/models.dart';
import '../kit.dart';
import '../scope.dart';
import '../theme.dart';

/// 다시 짠 일정에서 그 할 일이 언제 들어갔는지(예: '오늘 14:00', 하는 중이면 '지금').
String? _whereNow(Store store, String id) {
  final st = store.state;
  final t = store.now();
  for (final (k, label) in [(dateKey(t), '오늘'), (dateKey(addDays(t, 1)), '내일')]) {
    final b = planFor(st, k, t).blocks.where((x) => x.taskId == id && x.end.isAfter(t)).firstOrNull;
    if (b != null) return !b.start.isAfter(t) ? '지금' : '$label ${formatHm(b.start)}';
  }
  return null;
}

String _placedText(String? w, String fallback) => w == '지금' ? '지금 하는 조각에 이어서 해요' : (w != null ? '$w에 넣었어요' : fallback);

int _sumMinutes(Iterable<ScheduleBlock> bs) => bs.fold(0, (n, b) => n + b.minutes);

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  bool _showDone = false;

  TaskItem _blankTask() {
    final t = context.store.now();
    return TaskItem(
      id: '',
      title: '',
      estMinutes: TaskType.work.defaultMinutes,
      dueAt: addDays(t, 30),
      type: TaskType.work,
      priority: TaskPriority.normal,
      focus: true,
      createdAt: t,
    );
  }

  void _edit(TaskItem t) => showDsSheet<void>(context, title: t.id.isNotEmpty ? '할 일 고치기' : '할 일 추가', builder: (_) => _TaskSheet(task: t));

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final store = context.store;
    final now = context.ui.now;
    final c = context.ds;
    final todayKey = dateKey(now);
    final today = planFor(s, todayKey, now);
    final tomorrow = planFor(s, dateKey(addDays(now, 1)), now);
    final open = s.tasks.where((t) => !t.done).toList();
    final done = s.tasks.where((t) => t.done).toList();

    // AI 추천 순서(며칠 배운 뒤부터)
    final prefs = learnPrefs(s.learning);
    final suggestion = prefs != null ? suggestOrder(open, prefs, now) : null;
    final showSuggestion = suggestion != null && s.learning.dismissedDay != todayKey;
    final learnedDays = {...s.learning.reorders.map((r) => dateKey(r.at)), ...s.learning.completions.map((x) => dateKey(x.at))}.length;

    String placement(TaskItem t) {
      if (s.observation?.phase == ObservationPhase.recording) return '첫날 기록이 끝나면 일정에 넣어요';
      final tb = today.blocks.where((b) => b.taskId == t.id && !b.end.isBefore(now)).toList();
      if (tb.isNotEmpty) return '오늘 ${formatHm(tb.first.start)}부터 ${formatDuration(_sumMinutes(tb))}';
      final past = today.blocks.where((b) => b.taskId == t.id).toList();
      if (past.isNotEmpty && !s.eveningDone.contains(todayKey)) return '오늘 ${formatHm(past.first.start)}에 잡혀 있었어요 · 저녁 확인에서 반영해요';
      final nb = tomorrow.blocks.where((b) => b.taskId == t.id).toList();
      if (nb.isNotEmpty) return '내일 ${formatHm(nb.first.start)}부터 ${formatDuration(_sumMinutes(nb))}';
      if (tomorrow.plan.deferred.any((x) => x.taskId == t.id)) return '빈 시간이 부족해 모레 이후로 넘겨요';
      return '모레 이후 일정에 넣어요';
    }

    final learned = learnedDays < learnDays ? learnedDays : learnDays;

    return ScreenList(children: [
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(children: [
          Expanded(child: Semantics(header: true, child: Text('할 일', style: DsText.title.copyWith(color: c.ink)))),
          DsButton.primary('추가', small: true, icon: DsIcons.plus, onPressed: () => _edit(_blankTask())),
        ]),
      ),
      const LabelText('위에 있는 일부터 빈 시간에 자동으로 넣어요. 오른쪽 손잡이를 끌어 순서를 바꾸세요.'),
      if (showSuggestion) _SuggestionCard(open: open, suggestion: suggestion, days: prefs!.days),
      if (prefs == null && open.length >= 2)
        Semantics(
          label: 'AI 학습 진행',
          container: true,
          child: CustomPaint(
            painter: _DashedBorder(color: c.lineBtn, radius: 14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                const _AiBadge(),
                const SizedBox(width: 10),
                Expanded(child: LabelText('우선순위를 배우는 중 · $learned/$learnDays일. 순서를 바꾸거나 할 일을 끝내면 배워요.')),
                const SizedBox(width: 10),
                SizedBox(
                  width: 54,
                  height: 6,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: Stack(children: [
                      Positioned.fill(child: ColoredBox(color: c.future)),
                      FractionallySizedBox(widthFactor: learned / learnDays, heightFactor: 1, child: ColoredBox(color: c.accent)),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      Semantics(
        label: '진행 중인 할 일',
        container: true,
        child: DsCard(list: true, children: [
          if (open.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text('할 일이 없어요. 추가하면 일정에 자동으로 들어가요.', textAlign: TextAlign.center, style: DsText.body.copyWith(color: c.muted)),
            )
          else
            _SortableTasks(
              items: open,
              onReorder: (ids) => notifyPlan(context, store.reorderTasks(ids), '새 순서로 남은 일정을 바로 다시 짰어요', '순서를 바꿨어요'),
              itemBuilder: (t, i, handle) => _TaskRow(task: t, index: i, handle: handle, placement: placement(t), onEdit: () => _edit(t)),
            ),
        ]),
      ),
      if (done.isNotEmpty)
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          DsButton('완료 ${done.length}개 ${_showDone ? '접기' : '보기'}', kind: BtnKind.ghost, small: true, onPressed: () => setState(() => _showDone = !_showDone)),
          if (_showDone) ...[
            const SizedBox(height: 6),
            DsCard(list: true, children: [
              for (var i = 0; i < done.length; i++)
                Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  decoration: BoxDecoration(border: i == done.length - 1 ? null : Border(bottom: BorderSide(color: c.line))),
                  child: Row(children: [
                    _TaskCheck(
                      checked: true,
                      label: '${done[i].title} 완료 취소',
                      onChanged: () {
                        final t = done[i];
                        notifyPlan(context, store.toggleTaskDone(t.id), '${t.title}${objectParticle(t.title)} 다시 일정에 넣었어요', '완료를 취소했어요');
                      },
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(done[i].title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DsText.base.copyWith(color: c.muted, decoration: TextDecoration.lineThrough, decorationColor: c.muted)),
                    ),
                    DsIconButton(DsIcons.trash,
                        iconSize: 18, label: '${done[i].title} 지우기', onPressed: () => notifyPlan(context, store.deleteTask(done[i].id), '지웠어요')),
                  ]),
                ),
            ]),
          ],
        ]),
    ]);
  }
}

// ---------------------------------------------------------------------------
// AI 추천 순서
// ---------------------------------------------------------------------------

class _AiBadge extends StatelessWidget {
  const _AiBadge();

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: LinearGradient(colors: [c.accent, Color.lerp(c.accent, c.surface, 0.25)!, c.task], stops: const [0, 0.5, 1]),
      ),
      child: Text('AI', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.44, color: c.accentInk)),
    );
  }
}

/// 앞에 앰버 점이 붙은 한 줄(.impact).
class _Impact extends StatelessWidget {
  const _Impact(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 7, right: 8),
        child: Container(width: 6, height: 6, decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle)),
      ),
      Expanded(child: Text(text, style: TextStyle(fontSize: 14, height: 20 / 14, color: c.ink))),
    ]);
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.open, required this.suggestion, required this.days});
  final List<TaskItem> open;
  final OrderSuggestion suggestion;
  final int days;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final store = context.store;
    return Semantics(
      label: 'AI 추천 순서',
      container: true,
      child: Container(
        padding: DsGap.cardPad,
        decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.accent), borderRadius: BorderRadius.circular(20)),
        child: DsStack(gap: 10, children: [
          Row(children: [
            const _AiBadge(),
            const SizedBox(width: 8),
            const Expanded(child: DsTitle('이 순서는 어때요?')),
            LabelText('$days일 동안 배운 순서'),
          ]),
          Column(children: [
            for (var i = 0; i < suggestion.order.length; i++)
              Builder(builder: (context) {
                final id = suggestion.order[i];
                final from = open.indexWhere((x) => x.id == id);
                final t = from >= 0 ? open[from] : null;
                return Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
                  child: Row(children: [
                    Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: c.surface2, shape: BoxShape.circle),
                      child: Text('${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.ink, fontFeatures: DsText.num)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(t?.title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, color: c.ink))),
                    if (from >= 0 && from != i)
                      Text(from > i ? '▲ ${from - i}' : '▼ ${i - from}',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: from > i ? c.accentStrong : c.muted)),
                  ]),
                );
              }),
          ]),
          for (final r in suggestion.reasons) _Impact(r),
          Row(children: [
            Expanded(
              child: DsButton.primary('이 순서로 바꾸기', block: true, onPressed: () {
                haptic(10);
                notifyPlan(context, store.reorderTasks(suggestion.order, byUser: false), 'AI 추천 순서로 남은 일정을 다시 짰어요', 'AI 추천 순서로 바꿨어요');
              }),
            ),
            const SizedBox(width: 8),
            DsButton('지금 순서 유지', onPressed: store.dismissOrderSuggestion),
          ]),
        ]),
      ),
    );
  }
}

/// 점선 테두리(.learn-bar).
class _DashedBorder extends CustomPainter {
  _DashedBorder({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 6) {
        canvas.drawPath(m.extractPath(d, (d + 3).clamp(0, m.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}

// ---------------------------------------------------------------------------
// 할 일 줄
// ---------------------------------------------------------------------------

class _TaskCheck extends StatelessWidget {
  const _TaskCheck({required this.checked, required this.onChanged, required this.label});
  final bool checked;
  final VoidCallback onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    return Semantics(
      checked: checked,
      label: label,
      button: true,
      child: Pressable(
        scale: 0.9,
        onTap: onChanged,
        child: SizedBox.square(
          dimension: 44,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: checked ? c.accent : Colors.transparent,
                border: Border.all(color: checked ? c.accent : c.lineBtn, width: 2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: checked ? DsIcon(DsIcons.check, size: 16, stroke: 2.5, color: c.bg) : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task, required this.index, required this.handle, required this.placement, required this.onEdit});
  final TaskItem task;
  final int index;
  final Widget handle;
  final String placement;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final s = context.app;
    final store = context.store;
    final t = task;
    final pm = store.taskPlanMinutes(t);
    final cal = calibrationForTask(s.durations, t);
    final usedUp = pm.remaining == 0 && t.doneMinutes > 0;
    final amount = usedUp
        ? '${formatDuration(pm.planned)} 다 씀'
        : (t.doneMinutes > 0 ? '남은 ${formatDuration(pm.remaining)}' : formatDuration(t.estMinutes));
    final first = index == 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: first ? c.accent : c.surface2, shape: BoxShape.circle),
              child: Text('${index + 1}',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: first ? c.accentInk : c.muted, fontFeatures: DsText.num)),
            ),
            Transform.translate(
              offset: const Offset(-2, 0),
              child: _TaskCheck(
                checked: false,
                label: '${t.title} 완료',
                onChanged: () {
                  haptic(10);
                  notifyPlan(context, store.toggleTaskDone(t.id), '${t.title} 끝! 남은 일정을 다시 짰어요', '${t.title} 끝!');
                },
              ),
            ),
            Expanded(
              child: Pressable(
                scale: 0.98,
                onTap: onEdit,
                semanticLabel: '${t.title} 고치기',
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: DsText.base.copyWith(fontWeight: FontWeight.w600, color: c.ink)),
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '${t.type.label} · $amount'),
                      if (cal != null && t.doneMinutes == 0)
                        TextSpan(text: ' → 일정엔 ${formatDuration(pm.planned)}', style: TextStyle(color: c.accentStrong, fontWeight: FontWeight.w600)),
                    ]),
                    style: DsText.label.copyWith(color: c.muted, fontFeatures: DsText.num),
                  ),
                  const SizedBox(height: 2),
                  Text(usedUp ? '잡은 시간을 다 썼어요' : placement,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: DsText.label.copyWith(color: c.accentStrong)),
                ]),
              ),
            ),
            handle,
          ]),
        ),
      ),
      if (usedUp)
        Semantics(
          label: '${t.title} 잡은 시간 다 씀',
          container: true,
          child: Padding(
            padding: const EdgeInsets.only(left: 34, bottom: 12),
            child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              const SizedBox(width: double.infinity, child: LabelText('다 끝냈어요? 덜 끝났으면 시간을 늘려 다시 넣어요')),
              DsButton.primary('끝났어요',
                  small: true, onPressed: () => notifyPlan(context, store.toggleTaskDone(t.id), '${t.title} 끝! 실제 걸린 시간을 다음 예상에 반영해요')),
              for (final m in const [30, 60])
                DsButton('+${formatDuration(m)}', small: true, onPressed: () {
                  final r = store.extendTask(t.id, m);
                  notifyPlan(context, r, '${formatDuration(m)} 더 · ${_placedText(_whereNow(store, t.id), '빈 시간이 생기면 넣어요')}');
                }),
            ]),
          ),
        ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// 끌어서 순서 바꾸기
// ---------------------------------------------------------------------------

class _SortableTasks extends StatelessWidget {
  const _SortableTasks({required this.items, required this.onReorder, required this.itemBuilder});
  final List<TaskItem> items;
  final ValueChanged<List<String>> onReorder;
  final Widget Function(TaskItem t, int i, Widget handle) itemBuilder;

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      buildDefaultDragHandles: false,
      itemCount: items.length,
      onReorderStart: (_) => haptic(12),
      // Flutter 3.24~3.41 모두에서 쓰려고 onReorder를 쓴다(새 버전의 onReorderItem은 옛 버전에 없다).
      // ignore: deprecated_member_use
      onReorder: (from, to) {
        if (to > from) to -= 1;
        if (from == to) return;
        haptic(5);
        final ids = [for (final t in items) t.id];
        final m = ids.removeAt(from);
        ids.insert(to, m);
        onReorder(ids);
      },
      proxyDecorator: (child, index, animation) => AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          final v = reduce ? 1.0 : Curves.easeOut.transform(animation.value);
          return Transform.scale(
            scale: lerpDouble(1, 1.02, v)!,
            child: Material(
              color: c.surface,
              elevation: 0,
              borderRadius: BorderRadius.circular(14),
              shadowColor: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.35 * v), blurRadius: 30, offset: const Offset(0, 12))],
                ),
                child: child,
              ),
            ),
          );
        },
        child: child,
      ),
      itemBuilder: (context, i) {
        final t = items[i];
        final handle = ReorderableDragStartListener(
          index: i,
          child: Semantics(
            label: '${t.title} 순서 바꾸기, 끌어서 이동',
            button: true,
            child: Transform.translate(
              offset: const Offset(10, 0),
              child: SizedBox(width: 44, height: 48, child: Center(child: _HandleLines(color: c.faint))),
            ),
          ),
        );
        return Container(
          key: ValueKey(t.id),
          decoration: BoxDecoration(color: c.surface, border: i == items.length - 1 ? null : Border(bottom: BorderSide(color: c.line))),
          child: itemBuilder(t, i, handle),
        );
      },
    );
  }
}

/// 손잡이(가로줄 세 개, 20px 칸에 선 굵기 2 — 웹과 같은 모양).
class _HandleLines extends StatelessWidget {
  const _HandleLines({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 20 * 14 / 24 + 2,
        height: 20 * 10 / 24 + 2,
        child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          for (var i = 0; i < 3; i++) Container(height: 2, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(1))),
        ]),
      );
}

// ---------------------------------------------------------------------------
// 할 일 추가·고치기: 이름, 종류, 걸리는 시간만
// ---------------------------------------------------------------------------

const _quickMinutes = [15, 30, 60, 90, 120, 180];

class _TaskSheet extends StatefulWidget {
  const _TaskSheet({required this.task});
  final TaskItem task;

  @override
  State<_TaskSheet> createState() => _TaskSheetState();
}

class _TaskSheetState extends State<_TaskSheet> {
  late TaskItem _t = widget.task;
  late bool _minutesTouched = widget.task.id.isNotEmpty;
  late final _title = TextEditingController(text: widget.task.title);
  late final _minutes = TextEditingController(text: '${widget.task.estMinutes}');

  @override
  void dispose() {
    _title.dispose();
    _minutes.dispose();
    super.dispose();
  }

  void _setMinutes(int m, {bool syncField = true}) {
    _minutesTouched = true;
    setState(() => _t = _t.copyWith(estMinutes: m));
    if (syncField) _minutes.text = '$m';
  }

  void _save() {
    final store = context.store;
    final title = _title.text.trim();
    if (title.isEmpty) return;
    haptic(10);
    final isNew = widget.task.id.isEmpty;
    final id = isNew ? Store.newId('task') : widget.task.id;
    final r = store.saveTask(_t.copyWith(id: id, title: title, focus: focusByType(_t.type), createdAt: _t.createdAt ?? store.now()));
    final w = _whereNow(store, id);
    notifyPlan(context, r, '$title · ${_placedText(w, '일정을 다시 짰어요')}', isNew ? '$title · ${_placedText(w, '빈 시간이 생기면 자동으로 넣어요')}' : '저장했어요');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ds;
    final s = context.app;
    final store = context.store;
    final cal = calibrationForTask(s.durations, _t);
    final planned = store.taskPlanMinutes(_t).planned;
    final canSave = _title.text.trim().isNotEmpty;
    return DsStack(children: [
      DsField(
        label: '업무 이름',
        child: TextField(
          controller: _title,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _save(),
          style: TextStyle(fontSize: 17, color: c.ink),
          decoration: dsInput(context, hint: '예: 분기 보고서 작성').copyWith(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.lineStrong)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.accent, width: 2)),
          ),
        ),
      ),
      DsField(
        label: '업무 종류',
        child: Semantics(
          label: '업무 종류',
          container: true,
          child: ChipWrap(children: [
            for (final k in TaskType.values)
              DsChip(
                label: k.label,
                selected: _t.type == k,
                onTap: () {
                  setState(() => _t = _t.copyWith(type: k, estMinutes: _minutesTouched ? null : k.defaultMinutes));
                  if (!_minutesTouched) _minutes.text = '${k.defaultMinutes}';
                },
              ),
          ]),
        ),
      ),
      DsField(
        label: '걸리는 시간 · 모르면 종류별 기본값',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Semantics(
            label: '걸리는 시간',
            container: true,
            child: ChipWrap(children: [
              for (final m in _quickMinutes) DsChip(label: formatDuration(m), selected: _t.estMinutes == m, onTap: () => _setMinutes(m)),
            ]),
          ),
          const SizedBox(height: 8),
          Row(children: [
            SizedBox(
              width: 110,
              child: Semantics(
                label: '직접 입력(분)',
                child: TextField(
                  controller: _minutes,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                  style: TextStyle(fontSize: 15, color: c.ink, fontFeatures: DsText.num),
                  decoration: dsInput(context),
                  onChanged: (v) {
                    final n = int.tryParse(v) ?? 5;
                    _setMinutes(n < 5 ? 5 : n, syncField: false);
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(child: LabelText('분 · 50분씩 나눠 빈 시간에 넣어요')),
          ]),
          if (cal != null) ...[
            const SizedBox(height: 8),
            _Impact('${calibrationText(_t.title, cal, _t.type.label)} · 일정에는 ${formatDuration(planned)} 잡아요'),
          ],
        ]),
      ),
      if (_t.doneMinutes > 0) LabelText('지금까지 ${formatDuration(_t.doneMinutes)} 했어요'),
      Row(children: [
        if (widget.task.id.isNotEmpty) ...[
          DsButton('지우기', kind: BtnKind.danger, onPressed: () {
            notifyPlan(context, store.deleteTask(widget.task.id), '지웠어요. 남은 일정을 다시 짰어요', '지웠어요');
            Navigator.of(context).pop();
          }),
          const SizedBox(width: 8),
        ],
        Expanded(child: DsButton.primary('저장', block: true, onPressed: canSave ? _save : null)),
      ]),
    ]);
  }
}
