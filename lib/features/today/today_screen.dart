/// «Сегодня»: день, праздник, человек дня и календарь месяца.
///
/// Отдельной вкладки под календарь нет намеренно: сам по себе он пуст 350 дней
/// в году и нужен ровно в ту секунду, когда открываешь приложение. Поэтому он
/// живёт здесь, рядом с ответом на вопрос «что сегодня».
///
/// Первая строка экрана — возвращение в чтение. Текст остаётся главным, и
/// витрина перед ним обязана уводить обратно одним касанием.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/calendar/church_calendar.dart';
import '../../core/text/bible_reference.dart';
import '../../core/theme/design.dart';
import '../../data/entity_repository.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../entity/entity_page.dart';

/// Выбранный в сетке день. null — сегодняшний.
final _selectedDayProvider = StateProvider<DateTime?>((ref) => null);

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(settingsProvider).colors;
    final tradition = ref.watch(traditionProvider);
    final today = DateTime.now();
    final selected = ref.watch(_selectedDayProvider) ?? today;
    final isToday = selected.year == today.year &&
        selected.month == today.month &&
        selected.day == today.day;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: Text(formatDayTitle(today)),
        actions: [_TraditionButton(tradition: tradition)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            Insets.screen, 4, Insets.screen, 40),
        children: [
          const _ContinueReading(),
          const SizedBox(height: Insets.section),
          SectionTitle(isToday ? 'Сегодня' : formatDayShort(selected)),
          const SizedBox(height: 10),
          _FeastBlock(date: selected, tradition: tradition, isToday: isToday),
          const SizedBox(height: Insets.section),
          SectionTitle('Человек дня'),
          const SizedBox(height: 10),
          _PersonOfDay(date: today),
          const SizedBox(height: Insets.section),
          SectionTitle(monthName(selected.month)),
          const SizedBox(height: 10),
          _MonthGrid(month: selected, today: today, tradition: tradition),
        ],
      ),
    );
  }
}

class _ContinueReading extends ConsumerWidget {
  const _ContinueReading();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(settingsProvider).colors;
    final pos = ref.watch(positionProvider);
    final books = ref.watch(booksProvider).valueOrNull ?? const <Book>[];
    final book = books.where((b) => b.id == pos.bookId).firstOrNull;

    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () =>
            openInReader(ref, bookId: pos.bookId, chapter: pos.chapter),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              Icon(Icons.menu_book_rounded, size: 20, color: c.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Продолжить чтение',
                        style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            color: c.faint)),
                    const SizedBox(height: 2),
                    Text(
                      book == null
                          ? 'Библия'
                          : '${book.name} ${pos.chapter}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: c.text),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: c.faint),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeastBlock extends ConsumerWidget {
  const _FeastBlock({
    required this.date,
    required this.tradition,
    required this.isToday,
  });

  final DateTime date;
  final ChurchTradition tradition;
  final bool isToday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(settingsProvider).colors;
    final feasts = feastsOn(date, tradition);

    if (feasts.isEmpty) {
      final next = nextFeast(date, tradition);
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isToday ? 'Сегодня праздника нет' : 'В этот день праздника нет',
              style: TextStyle(
                  fontFamily: 'Inter', fontSize: 14, color: c.muted),
            ),
            if (next != null) ...[
              const SizedBox(height: 8),
              Text(
                'Ближайший: ${next.feast.name}, ${formatDayShort(next.date)}',
                style: TextStyle(
                    fontFamily: 'Inter', fontSize: 13, color: c.faint),
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      children: [for (final f in feasts) _FeastCard(feast: f)],
    );
  }
}

class _FeastCard extends ConsumerWidget {
  const _FeastCard({required this.feast});
  final Feast feast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(settingsProvider).colors;
    final books = ref.watch(booksProvider).valueOrNull ?? const <Book>[];
    final book = feast.bookId == null
        ? null
        : books.where((b) => b.id == feast.bookId).firstOrNull;

    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.gap),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(feast.name,
              style: TextStyle(
                  fontFamily: 'Literata',
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                  color: c.text)),
          const SizedBox(height: 8),
          Text(feast.summary,
              style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  height: 1.5,
                  color: c.muted)),
          if (feast.inScripture && book != null) ...[
            const SizedBox(height: 12),
            Material(
              color: c.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  final db = ref.read(bibleDbProvider).valueOrNull;
                  final vkey = db?.vkeyFor(ref.read(translationProvider),
                      feast.bookId!, feast.chapter!, feast.verse ?? 1);
                  openInReader(ref,
                      bookId: feast.bookId!,
                      chapter: feast.chapter!,
                      vkey: vkey);
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Читать: ${bookLabel(book)} ${feast.reference}',
                          style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: c.accent)),
                      const SizedBox(width: 3),
                      Icon(Icons.arrow_forward_rounded,
                          size: 15, color: c.accent),
                    ],
                  ),
                ),
              ),
            ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PersonOfDay extends ConsumerWidget {
  const _PersonOfDay({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(settingsProvider).colors;
    final db = ref.watch(bibleDbProvider).valueOrNull;
    final person = db?.personOfTheDay(date);
    if (person == null) return const SizedBox.shrink();

    // Подпись собираем из своих данных, а не из статьи: все статьи в базе
    // английские, и на русском экране такая строка читается как поломка.
    final books = ref.watch(booksProvider).valueOrNull ?? const <Book>[];
    final first = person.firstVkey == null
        ? null
        : db?.verseByKey(ref.watch(translationProvider), person.firstVkey!);
    final firstBook = first == null
        ? null
        : books.where((b) => b.id == first.bookId).firstOrNull;
    final facts = [
      '${person.refCount} ${mentionsWord(person.refCount)} в Писании',
      if (first != null && firstBook != null)
        'впервые ${bookLabel(firstBook)} ${first.chapter}:${first.verse}',
    ].join(' · ');

    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => EntityPage(entityId: person.id))),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(person.displayName,
                  style: TextStyle(
                      fontFamily: 'Literata',
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      color: c.text)),
              const SizedBox(height: 6),
              Text(facts,
                  style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      height: 1.5,
                      color: c.muted)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text('Кто это за 30 секунд',
                      style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: c.accent)),
                  const SizedBox(width: 3),
                  Icon(Icons.arrow_forward_rounded, size: 15, color: c.accent),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthGrid extends ConsumerWidget {
  const _MonthGrid({
    required this.month,
    required this.today,
    required this.tradition,
  });

  final DateTime month;
  final DateTime today;
  final ChurchTradition tradition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(settingsProvider).colors;
    final marked = feastDaysOfMonth(month.year, month.month, tradition);
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // В русском календаре неделя начинается с понедельника.
    final leading = first.weekday - 1;

    final cells = <Widget>[];
    for (var i = 0; i < leading; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var day = 1; day <= daysInMonth; day++) {
      final isToday = today.year == month.year &&
          today.month == month.month &&
          today.day == day;
      final isSelected = month.day == day;
      cells.add(_DayCell(
        day: day,
        isToday: isToday,
        isSelected: isSelected && !isToday,
        hasFeast: marked.contains(day),
        onTap: () => ref.read(_selectedDayProvider.notifier).state =
            DateTime(month.year, month.month, day),
      ));
    }

    return Column(
      children: [
        Row(
          children: [
            for (final w in weekdayLetters)
              Expanded(
                child: Center(
                  child: Text(w,
                      style: TextStyle(
                          fontFamily: 'Inter', fontSize: 11, color: c.faint)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.0,
          children: cells,
        ),
      ],
    );
  }
}

class _DayCell extends ConsumerWidget {
  const _DayCell({
    required this.day,
    required this.isToday,
    required this.isSelected,
    required this.hasFeast,
    required this.onTap,
  });

  final int day;
  final bool isToday;
  final bool isSelected;
  final bool hasFeast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(settingsProvider).colors;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: isToday
              ? c.accent
              : isSelected
                  ? c.accent.withValues(alpha: 0.14)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$day',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                  color: isToday ? Colors.white : c.text,
                )),
            const SizedBox(height: 3),
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: !hasFeast
                    ? Colors.transparent
                    : isToday
                        ? Colors.white
                        : c.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TraditionButton extends ConsumerWidget {
  const _TraditionButton({required this.tradition});
  final ChurchTradition tradition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(settingsProvider).colors;
    return PopupMenuButton<ChurchTradition>(
      tooltip: 'Традиция',
      color: c.surface,
      onSelected: (t) => ref.read(traditionProvider.notifier).set(t),
      itemBuilder: (_) => [
        for (final t in ChurchTradition.values)
          PopupMenuItem(
            value: t,
            child: Row(
              children: [
                Icon(
                  t == tradition
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 18,
                  color: t == tradition ? c.accent : c.faint,
                ),
                const SizedBox(width: 10),
                Text(t.title,
                    style: TextStyle(
                        fontFamily: 'Inter', fontSize: 14, color: c.text)),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tradition.title,
                style: TextStyle(
                    fontFamily: 'Inter', fontSize: 13, color: c.muted)),
            Icon(Icons.expand_more_rounded, size: 16, color: c.muted),
          ],
        ),
      ),
    );
  }
}

