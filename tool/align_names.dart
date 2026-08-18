/// Сопоставление сущностей TIPNR с их именами в русском тексте.
///
/// TIPNR привязан к английским переводам и не может сказать, каким словом
/// Синодальный называет Аарона. Но он говорит главное: в каких стихах эта
/// сущность присутствует. Отсюда алгоритм:
///
///   1. взять все стихи сущности в Синодальном;
///   2. найти слово, которое есть почти в каждом из них и почти нигде больше;
///   3. подтвердить догадку транслитерацией английского имени.
///
/// Контекстная дизамбигуация тёзок не нужна: какой из пяти Марий принадлежит
/// стих, уже известно из данных. Это делает привязку на порядок надёжнее
/// обычного распознавания именованных сущностей.
library;

import 'dart:math';

import 'package:holy_bible/core/text/russian_stemmer.dart';

/// Длина префикса, по которому словоформы одного имени считаются одним словом.
///
/// Стемминг здесь неприменим: он обрезает имена по правилам нарицательных
/// слов и разводит формы одного имени («Иерусалим» → «иерусал», но
/// «Иерусалиме» → «иерусалим»). У русских имён меняется только окончание,
/// поэтому надёжный признак — общее начало. Четыре буквы найдены опытным
/// путём: пять уже разводит «Петр» и «Петра», три склеивает разные имена.
const namePrefixLength = 4;

String nameKey(String word) {
  final w = word.toLowerCase().replaceAll('ё', 'е');
  return w.length <= namePrefixLength ? w : w.substring(0, namePrefixLength);
}

/// Вхождение имени в конкретный стих — готовый спан для таблицы mentions.
class Occurrence {
  final int vkey;
  final int start;
  final int end;
  final String surface;
  Occurrence(this.vkey, this.start, this.end, this.surface);
}

class NameMatch {
  final String key;
  final String surface; // самая частая словоформа
  final Map<String, int> formCounts; // все словоформы и как часто встречались
  final double coverage; // доля стихов сущности, где слово есть
  final double specificity; // доля всех вхождений, попавших в эти стихи
  final double translit; // похожесть на английское имя
  final List<Occurrence> occurrences;

  NameMatch(this.key, this.surface, this.formCounts, this.coverage,
      this.specificity, this.translit, this.occurrences);

  Iterable<String> get forms => formCounts.keys;

  double get score => coverage * specificity * (1 + 2 * translit);

  @override
  String toString() => '$surface(${score.toStringAsFixed(2)} '
      'cov=${coverage.toStringAsFixed(2)} spec=${specificity.toStringAsFixed(2)} '
      'tr=${translit.toStringAsFixed(2)})';
}

const _translitMap = {
  'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ё': 'e',
  'ж': 'j', 'з': 'z', 'и': 'i', 'й': 'i', 'к': 'k', 'л': 'l', 'м': 'm',
  'н': 'n', 'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u',
  'ф': 'f', 'х': 'h', 'ц': 'ts', 'ч': 'ch', 'ш': 'sh', 'щ': 'sh', 'ъ': '',
  'ы': 'i', 'ь': '', 'э': 'e', 'ю': 'iu', 'я': 'ia',
};

String _translit(String ru) {
  final b = StringBuffer();
  for (final c in ru.toLowerCase().split('')) {
    b.write(_translitMap[c] ?? c);
  }
  return _collapse(b.toString());
}

/// Приводит английское написание к тому же огрублённому алфавиту.
/// Синодальный передавал имена с греческого напрямую, английские переводы —
/// через латинскую традицию, и расхождения систематичны: Jerusalem/Иерусалим,
/// Nicodemus/Никодим, Christ/Христос.
String _normEnglish(String en) {
  var s = en.toLowerCase();
  s = s.replaceAll('ph', 'f').replaceAll('th', 't').replaceAll('ch', 'h');
  s = s.replaceAll('c', 'k').replaceAll('q', 'k').replaceAll('x', 'ks');
  s = s.replaceAll('j', 'i').replaceAll('y', 'i').replaceAll('w', 'v');
  s = s.replaceAll(RegExp(r'[^a-z]'), '');
  return _collapse(s);
}

/// Схлопывает удвоенные буквы: Aaron/Аарон.
String _collapse(String s) {
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && s[i] == s[i - 1]) continue;
    b.write(s[i]);
  }
  return b.toString();
}

int editDistance(String a, String b) => _levenshtein(a, b);

int _levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  var cur = List<int>.filled(b.length + 1, 0);
  for (var i = 0; i < a.length; i++) {
    cur[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      final cost = a[i] == b[j] ? 0 : 1;
      cur[j + 1] = min(min(cur[j] + 1, prev[j + 1] + 1), prev[j] + cost);
    }
    final t = prev;
    prev = cur;
    cur = t;
  }
  return prev[b.length];
}

/// Похожесть русского слова на английское имя. Общее начало учитывается
/// отдельно от расстояния правок: расходятся имена обычно в окончаниях
/// (Никодим / Nicodemus), а корень совпадает.
double translitSimilarity(String ru, String en) {
  final a = _translit(ru);
  final b = _normEnglish(en);
  if (a.isEmpty || b.isEmpty) return 0;
  final byLev = 1.0 - _levenshtein(a, b) / max(a.length, b.length);
  var pref = 0;
  while (pref < a.length && pref < b.length && a[pref] == b[pref]) {
    pref++;
  }
  final byPref = pref / min(a.length, b.length);
  return max(0.0, 0.5 * byLev + 0.5 * byPref);
}

/// Считает, в скольких стихах встречается каждый префиксный ключ.
/// Нужно, чтобы отличить имя от частотного слова: «Аарон» встречается только
/// в стихах про Аарона, а «сказал» — везде.
///
/// Учитываются лишь слова с заглавной буквы. Иначе частота ключа складывается
/// из нарицательных слов с тем же началом — префикс «нико» собирает «никого»,
/// «никому», «никогда» и топит настоящего Никодима.
Map<String, int> buildKeyFrequency(Iterable<String> allVerses,
    {bool onlyCapitalized = true}) {
  final df = <String, int>{};
  for (final text in allVerses) {
    final seen = <String>{};
    for (final t in tokenizeWithOffsets(text)) {
      if (onlyCapitalized && !startsUpper(t.word)) continue;
      final k = nameKey(t.word);
      if (k.length < 3) continue;
      if (seen.add(k)) df[k] = (df[k] ?? 0) + 1;
    }
  }
  return df;
}

/// Подбирает русские имена сущности и сразу возвращает спаны вхождений.
///
/// [verses] — стихи этой сущности: ключ стиха и его русский текст.
/// [df] — сколько всего стихов Библии содержат данный префиксный ключ.
/// [requireUpper] — искать только среди слов с заглавной буквы. Верно для
/// людей и мест, но не для понятий: «фарисеи», «суббота», «пасха» в
/// Синодальном пишутся со строчной, и такой фильтр терял их целиком.
List<NameMatch> findNames({
  required Map<int, String> verses,
  required Map<String, int> df,
  required String englishName,
  int limit = 3,
  bool requireUpper = true,
}) {
  if (verses.isEmpty) return const [];

  final hits = <String, int>{};
  final surfaces = <String, Map<String, int>>{};
  final occurrences = <String, List<Occurrence>>{};
  final everUpper = <String>{};

  for (final entry in verses.entries) {
    final seen = <String>{};
    for (final t in tokenizeWithOffsets(entry.value)) {
      if (requireUpper && !startsUpper(t.word)) continue;
      final k = nameKey(t.word);
      if (k.length < 3) continue;
      if (!requireUpper || startsUpper(t.word)) everUpper.add(k);
      if (seen.add(k)) hits[k] = (hits[k] ?? 0) + 1;
      (surfaces[k] ??= {})[t.word] = (surfaces[k]?[t.word] ?? 0) + 1;
      (occurrences[k] ??= [])
          .add(Occurrence(entry.key, t.start, t.end, t.word));
    }
  }

  final out = <NameMatch>[];
  for (final e in hits.entries) {
    if (!everUpper.contains(e.key)) continue;
    final total = df[e.key] ?? e.value;
    if (total == 0) continue;
    final forms = surfaces[e.key]!;
    final best = forms.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    out.add(NameMatch(
      e.key,
      best,
      forms,
      e.value / verses.length,
      e.value / total,
      translitSimilarity(best, englishName),
      occurrences[e.key]!,
    ));
  }

  out.sort((a, b) => b.score.compareTo(a.score));
  if (out.isEmpty) return out;

  // Оставляем лидера и всё сопоставимое с ним: у людей и мест нередко
  // несколько имён (Иерусалим — он же Сион и Салим).
  final top = out.first.score;
  return out.where((c) => c.score >= top * 0.45).take(limit).toList();
}
