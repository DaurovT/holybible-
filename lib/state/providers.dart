/// Провайдеры приложения.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/calendar/church_calendar.dart';
import '../core/theme/reading_theme.dart';
import '../data/bible_database.dart';
import '../data/models.dart';
import '../data/strongs_database.dart';

final prefsProvider = FutureProvider<SharedPreferences>(
    (ref) => SharedPreferences.getInstance());

final bibleDbProvider = FutureProvider<BibleDatabase>((ref) async {
  final db = await BibleDatabase.open();
  ref.onDispose(db.dispose);
  return db;
});

/// Словарь Стронга. Открывается лениво: файл на 36 МБ копируется только тогда,
/// когда о словах оригинала спросили в первый раз.
final strongsDbProvider = FutureProvider<StrongsDatabase>((ref) async {
  final db = await StrongsDatabase.open();
  ref.onDispose(db.dispose);
  return db;
});

// ── Настройки чтения ──────────────────────────────────────────────────────

class SettingsNotifier extends StateNotifier<ReadingSettings> {
  SettingsNotifier(this._prefs, super.state);

  static const _key = 'reading_settings';
  final SharedPreferences? _prefs;

  static ReadingSettings load(SharedPreferences? p) {
    final raw = p?.getString(_key);
    if (raw == null) return const ReadingSettings();
    try {
      return ReadingSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const ReadingSettings();
    }
  }

  void update(ReadingSettings next) {
    state = next;
    _prefs?.setString(_key, jsonEncode(next.toJson()));
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, ReadingSettings>((ref) {
  final prefs = ref.watch(prefsProvider).valueOrNull;
  return SettingsNotifier(prefs, SettingsNotifier.load(prefs));
});

// ── Текущий перевод и позиция чтения ──────────────────────────────────────

class TranslationNotifier extends StateNotifier<String> {
  TranslationNotifier(this._prefs)
      : super(_prefs?.getString(_key) ?? 'syn');
  static const _key = 'translation';
  final SharedPreferences? _prefs;

  void set(String id) {
    state = id;
    _prefs?.setString(_key, id);
  }
}

final translationProvider =
    StateNotifierProvider<TranslationNotifier, String>((ref) =>
        TranslationNotifier(ref.watch(prefsProvider).valueOrNull));

/// Второй перевод для параллельного режима. null — режим выключен.
class ParallelNotifier extends StateNotifier<String?> {
  ParallelNotifier(this._prefs) : super(_prefs?.getString(_key));
  static const _key = 'parallel_translation';
  final SharedPreferences? _prefs;

  void set(String? id) {
    state = id;
    if (id == null) {
      _prefs?.remove(_key);
    } else {
      _prefs?.setString(_key, id);
    }
  }
}

final parallelTranslationProvider =
    StateNotifierProvider<ParallelNotifier, String?>((ref) =>
        ParallelNotifier(ref.watch(prefsProvider).valueOrNull));

final translationsProvider = FutureProvider<List<Translation>>((ref) async {
  final db = await ref.watch(bibleDbProvider.future);
  return db.translations();
});

final booksProvider = FutureProvider<List<Book>>((ref) async {
  final db = await ref.watch(bibleDbProvider.future);
  return db.books(ref.watch(translationProvider));
});

/// Позиция чтения: книга и глава. Сохраняется между запусками — вернуться
/// туда, где остановился, важнее любой другой функции навигации.
class ReadingPosition {
  final String bookId;
  final int chapter;
  const ReadingPosition(this.bookId, this.chapter);
}

class PositionNotifier extends StateNotifier<ReadingPosition> {
  PositionNotifier(this._prefs)
      : super(ReadingPosition(
          _prefs?.getString(_bookKey) ?? 'JHN',
          _prefs?.getInt(_chapterKey) ?? 1,
        ));

  static const _bookKey = 'pos_book';
  static const _chapterKey = 'pos_chapter';
  final SharedPreferences? _prefs;

  void set(String bookId, int chapter) {
    state = ReadingPosition(bookId, chapter);
    _prefs?.setString(_bookKey, bookId);
    _prefs?.setInt(_chapterKey, chapter);
  }
}

final positionProvider =
    StateNotifierProvider<PositionNotifier, ReadingPosition>((ref) =>
        PositionNotifier(ref.watch(prefsProvider).valueOrNull));

/// Куда переходили в последнее время.
///
/// Навигация почти всегда возвращает в те же несколько мест, и список недавних
/// экономит целый экран выбора.
class RecentPlacesNotifier extends StateNotifier<List<ReadingPosition>> {
  RecentPlacesNotifier(this._prefs) : super(_load(_prefs));

  static const _key = 'recent_places';
  static const _limit = 12;
  final SharedPreferences? _prefs;

  static List<ReadingPosition> _load(SharedPreferences? p) {
    final out = <ReadingPosition>[];
    for (final s in p?.getStringList(_key) ?? const <String>[]) {
      final parts = s.split(':');
      final chapter = parts.length == 2 ? int.tryParse(parts[1]) : null;
      if (chapter != null) out.add(ReadingPosition(parts[0], chapter));
    }
    return out;
  }

  void remember(String bookId, int chapter) {
    final next = <ReadingPosition>[
      ReadingPosition(bookId, chapter),
      for (final p in state)
        if (p.bookId != bookId || p.chapter != chapter) p,
    ];
    if (next.length > _limit) next.removeRange(_limit, next.length);
    state = next;
    _prefs?.setStringList(
        _key, [for (final p in next) '${p.bookId}:${p.chapter}']);
  }
}

final recentPlacesProvider =
    StateNotifierProvider<RecentPlacesNotifier, List<ReadingPosition>>((ref) =>
        RecentPlacesNotifier(ref.watch(prefsProvider).valueOrNull));

/// Христианская традиция: от неё зависят даты праздников и их состав.
/// Спрашивать при первом запуске пока не спрашиваем — по умолчанию православие,
/// поменять можно прямо на экране «Сегодня».
class TraditionNotifier extends StateNotifier<ChurchTradition> {
  TraditionNotifier(this._prefs)
      : super(ChurchTradition.parse(_prefs?.getString(_key)));

  static const _key = 'tradition';
  final SharedPreferences? _prefs;

  void set(ChurchTradition t) {
    state = t;
    _prefs?.setString(_key, t.name);
  }
}

final traditionProvider =
    StateNotifierProvider<TraditionNotifier, ChurchTradition>((ref) =>
        TraditionNotifier(ref.watch(prefsProvider).valueOrNull));

/// Просьба открыть конкретное место: из поиска, закладок, заметок, карточки
/// сущности.
///
/// Одной записи позиции недостаточно: лента чтения строится вокруг опоры,
/// которая считается при первом открытии экрана. Дальше менять `position`
/// бессмысленно — экран уже собран и никуда не поедет. Поэтому переход это
/// отдельное событие, которое читалка разбирает и сбрасывает.
typedef JumpTarget = ({String bookId, int chapter, int? vkey});

final jumpRequestProvider = StateProvider<JumpTarget?>((ref) => null);

/// Текущая вкладка. Живёт в провайдере, а не в состоянии оболочки, потому что
/// переключить её нужно и из «Моё» — оттуда, где закладка ведёт в текст.
final tabProvider = StateProvider<int>((ref) => 0);

/// Открыть место в читалке: просьба о переходе плюс переключение на чтение.
/// Пользуются и «Моё», и карточка сущности, и поиск.
void openInReader(WidgetRef ref,
    {required String bookId, required int chapter, int? vkey}) {
  ref.read(jumpRequestProvider.notifier).state =
      (bookId: bookId, chapter: chapter, vkey: vkey);
  ref.read(tabProvider.notifier).state = 0;
}

// ── Загрузка главы ────────────────────────────────────────────────────────

/// Плоский список всех глав Библии подряд: (книга, номер главы).
/// Нужен, чтобы экран чтения был одной непрерывной лентой, а не набором
/// отдельных экранов с перелистыванием.
final chapterIndexProvider = FutureProvider<List<(Book, int)>>((ref) async {
  final books = await ref.watch(booksProvider.future);
  return [
    for (final b in books)
      for (var c = 1; c <= b.chapters; c++) (b, c)
  ];
});

typedef ChapterRef = ({String translationId, String bookId, int chapter});

/// Те же стихи во втором переводе, разложенные по единому ключу стиха.
///
/// Сопоставление именно по vkey, а не по номерам главы и стиха: нумерация у
/// переводов расходится (в Синодальном 31169 стихов, в KJV — 31102), и
/// «тот же стих рядом» по номеру местами показывал бы соседний.
final parallelChapterProvider =
    FutureProvider.family<Map<int, Verse>, ChapterRef>((ref, key) async {
  final other = ref.watch(parallelTranslationProvider);
  if (other == null || other == key.translationId) return const {};
  final db = await ref.watch(bibleDbProvider.future);
  final primary = await ref.watch(chapterProvider(key).future);
  if (primary == null) return const {};
  return db.versesByKeys(other, [for (final v in primary.verses) v.vkey]);
});

final chapterProvider =
    FutureProvider.family<Chapter?, ChapterRef>((ref, key) async {
  final db = await ref.watch(bibleDbProvider.future);
  final books = await ref.watch(booksProvider.future);
  final book = books.where((b) => b.id == key.bookId).firstOrNull;
  if (book == null) return null;
  return db.chapter(key.translationId, book, key.chapter);
});
