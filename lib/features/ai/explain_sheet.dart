/// Панель разбора отрывка.
///
/// Устроена так, чтобы ответ ИИ всегда стоял рядом с источниками, на которых
/// он основан: текст, параллельные места, сущности отрывка, слово оригинала.
/// Это не украшение — именно проверяемость отличает полезный разбор от
/// правдоподобной выдумки, а Писание — та область, где выдумка недопустима.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/entity_repository.dart';
import '../../core/text/bible_reference.dart';
import '../../data/cross_ref_repository.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../entity/entity_sheet.dart';
import 'ai_service.dart';

enum ExplainMode {
  explain('Объяснить', [
    'Простыми словами',
    'Что имеется в виду',
    'Что означают отдельные слова',
    'Как это толковали',
    'Почему существуют разные трактовки',
  ]),
  context('Контекст', [
    'Исторический контекст',
    'Кто здесь действует',
    'Где это происходит',
    'Что было до и после',
  ]),
  whyMatters('Почему это важно', [
    'Роль в этой книге',
    'Связь с другими местами Библии',
    'Почему на это ссылаются',
  ]),
  ask('Задать вопрос', []);

  const ExplainMode(this.title, this.options);
  final String title;
  final List<String> options;
}

void showExplainSheet(
  BuildContext context, {
  required ExplainMode mode,
  required String reference,
  required String text,
  required List<Verse> verses,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ExplainSheet(
      mode: mode,
      reference: reference,
      text: text,
      verses: verses,
    ),
  );
}

class _ExplainSheet extends ConsumerStatefulWidget {
  const _ExplainSheet({
    required this.mode,
    required this.reference,
    required this.text,
    required this.verses,
  });

  final ExplainMode mode;
  final String reference;
  final String text;
  final List<Verse> verses;

  @override
  ConsumerState<_ExplainSheet> createState() => _ExplainSheetState();
}

class _ExplainSheetState extends ConsumerState<_ExplainSheet> {
  String? _selectedOption;
  final _question = TextEditingController();
  AiAnswer? _answer;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  Future<void> _ask(String prompt) async {
    setState(() {
      _loading = true;
      _error = null;
      _selectedOption = prompt;
    });
    try {
      final entities = await _entities();
      final answer = await ref.read(aiServiceProvider).explain(
            AiRequest(
              mode: widget.mode.name,
              instruction: prompt,
              reference: widget.reference,
              passage: widget.text,
              entityIds: entities.map((e) => e.id).toList(),
              crossReferences: _crossRefs(),
            ),
          );
      if (mounted) setState(() => _answer = answer);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<BibleEntity>> _entities() async {
    final db = await ref.read(bibleDbProvider.future);
    final ids = <String>{
      for (final v in widget.verses)
        for (final m in v.mentions)
          if (m.confidence >= 0.2) m.entityId
    };
    final list = db.entities(ids.toList());
    list.sort((a, b) => b.refCount.compareTo(a.refCount));
    return list;
  }

  /// Перекрёстные ссылки берём из данных, а не у модели: они выверены людьми
  /// и работают офлайн. Сначала слой OpenBible, затем разметка самого издания.
  List<String> _crossRefs() {
    final out = <String>[];
    final db = ref.read(bibleDbProvider).valueOrNull;
    if (db != null) {
      final books = ref.read(booksProvider).valueOrNull ?? const <Book>[];
      final refs = db.crossRefs(
        ref.read(translationProvider),
        [for (final v in widget.verses) v.vkey],
        limit: 12,
      );
      for (final r in refs) {
        final b = books.where((x) => x.id == r.bookId).firstOrNull;
        final label = b == null ? r.bookId : bookLabel(b);
        out.add(r.isRange
            ? '$label ${r.chapter}:${r.verse}–${r.verseEnd}'
            : '$label ${r.chapter}:${r.verse}');
      }
    }
    for (final v in widget.verses) {
      for (final seg in v.segments) {
        for (final r in seg.runs) {
          if (r.noteKind == 'x' && r.noteText != null) out.add(r.noteText!);
        }
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final c = s.colors;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 40),
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                    color: c.divider, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 18),
            Text(widget.mode.title,
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                    color: c.text)),
            const SizedBox(height: 14),

            // Сам отрывок всегда на виду: разбор без текста перед глазами
            // теряет смысл.
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: c.background,
                borderRadius: BorderRadius.circular(12),
                border: Border(
                    left: BorderSide(color: c.accent.withValues(alpha: 0.55), width: 3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.text,
                      style: TextStyle(
                          fontFamily: s.fontFamily,
                          fontSize: s.fontSize * 0.92,
                          height: 1.55,
                          color: c.text)),
                  const SizedBox(height: 8),
                  Text(widget.reference,
                      style: TextStyle(
                          fontFamily: 'Inter', fontSize: 12, color: c.muted)),
                ],
              ),
            ),
            const SizedBox(height: 20),

            if (widget.mode == ExplainMode.ask) ...[
              TextField(
                controller: _question,
                minLines: 1,
                maxLines: 4,
                style: TextStyle(
                    fontFamily: 'Inter', fontSize: 15, color: c.text),
                decoration: InputDecoration(
                  hintText: 'Например: почему именно «нищие»?',
                  hintStyle: TextStyle(color: c.faint, fontFamily: 'Inter'),
                  filled: true,
                  fillColor: c.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: _ask,
              ),
              const SizedBox(height: 12),
            ] else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final o in widget.mode.options)
                    _Chip(
                      label: o,
                      selected: _selectedOption == o,
                      onTap: () => _ask(o),
                    ),
                ],
              ),

            const SizedBox(height: 22),

            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 26),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_error != null)
              _Notice(message: _error!)
            else if (_answer != null)
              _AnswerView(answer: _answer!),

            const SizedBox(height: 26),
            _SourcesSection(verses: widget.verses, crossRefs: _crossRefs()),
          ],
        ),
      ),
    );
  }
}

class _Chip extends ConsumerWidget {
  const _Chip(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(settingsProvider).colors;
    return Material(
      color: selected ? c.accent.withValues(alpha: 0.14) : c.background,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(label,
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? c.accent : c.text)),
        ),
      ),
    );
  }
}

class _AnswerView extends ConsumerWidget {
  const _AnswerView({required this.answer});
  final AiAnswer answer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final c = s.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(answer.text,
            style: TextStyle(
                fontFamily: s.fontFamily,
                fontSize: s.fontSize * 0.92,
                height: 1.6,
                color: c.text)),
        if (answer.citations.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('ИСТОЧНИКИ ОТВЕТА',
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                  color: c.faint)),
          const SizedBox(height: 8),
          for (final cit in answer.citations)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('• ${cit.label} — ${cit.source}',
                  style: TextStyle(
                      fontFamily: 'Inter', fontSize: 13, color: c.muted)),
            ),
        ],
      ],
    );
  }
}

class _Notice extends ConsumerWidget {
  const _Notice({required this.message});
  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(settingsProvider).colors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: c.muted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    height: 1.5,
                    color: c.muted)),
          ),
        ],
      ),
    );
  }
}

/// Источники, доступные офлайн прямо сейчас: кто упомянут в отрывке и куда
/// ведут перекрёстные ссылки издания.
class _SourcesSection extends ConsumerWidget {
  const _SourcesSection({required this.verses, required this.crossRefs});

  final List<Verse> verses;
  final List<String> crossRefs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(settingsProvider).colors;
    final dbAsync = ref.watch(bibleDbProvider);

    final ids = <String>{
      for (final v in verses)
        for (final m in v.mentions)
          if (m.confidence >= 0.2) m.entityId
    };

    final entities = dbAsync.valueOrNull?.entities(ids.toList()) ?? const [];
    final sorted = [...entities]
      ..sort((a, b) => b.refCount.compareTo(a.refCount));

    if (sorted.isEmpty && crossRefs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(color: c.divider, height: 32),
        if (sorted.isNotEmpty) ...[
          Text('О КОМ И О ЧЁМ ЗДЕСЬ РЕЧЬ',
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                  color: c.faint)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in sorted)
                _Chip(
                  label: e.displayName,
                  selected: false,
                  onTap: () => showEntitySheet(context, e.id),
                ),
            ],
          ),
          const SizedBox(height: 20),
        ],
        if (crossRefs.isNotEmpty) ...[
          Text('ПАРАЛЛЕЛЬНЫЕ МЕСТА',
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                  color: c.faint)),
          const SizedBox(height: 8),
          for (final r in crossRefs.take(8))
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(r,
                  style: TextStyle(
                      fontFamily: 'Inter', fontSize: 13, color: c.muted)),
            ),
        ],
      ],
    );
  }
}
