/// Стеммер Snowball для русского языка.
///
/// Используется в двух местах и обязан давать одинаковый результат в обоих:
///   1. при сборке БД (`tool/build_bible_db.dart`) — индексируются основы слов;
///   2. при поиске в приложении — запрос приводится к тем же основам.
///
/// Именно поэтому реализация одна: если индекс и запрос разойдутся хотя бы в
/// одном правиле, поиск начнёт молча терять результаты.
library;

const _vowels = 'аеиоуыэюя';

bool _isVowel(String c) => _vowels.contains(c);

/// Окончания перечислены от длинных к коротким: правило Snowball требует
/// снимать самое длинное подходящее.
const _perfectiveGerund1 = ['вшись', 'вши', 'в'];
const _perfectiveGerund2 = ['ывшись', 'ившись', 'ывши', 'ивши', 'ыв', 'ив'];

const _adjective = [
  'ыми', 'ими', 'его', 'ого', 'ему', 'ому', 'ее', 'ие', 'ые', 'ое', 'ей',
  'ий', 'ый', 'ой', 'ем', 'им', 'ым', 'ом', 'их', 'ых', 'ую', 'юю', 'ая',
  'яя', 'ою', 'ею',
];

const _participle1 = ['ющ', 'ем', 'нн', 'вш', 'щ'];
const _participle2 = ['ующ', 'ивш', 'ывш'];

const _reflexive = ['ся', 'сь'];

const _verb1 = [
  'ешь', 'нно', 'ете', 'йте', 'ла', 'на', 'ли', 'ем', 'ло', 'но', 'ет',
  'ют', 'ны', 'ть', 'й', 'л', 'н',
];
const _verb2 = [
  'ейте', 'уйте', 'ила', 'ыла', 'ена', 'ите', 'или', 'ыли', 'ило', 'ыло',
  'ено', 'ует', 'уют', 'ены', 'ить', 'ыть', 'ишь', 'ей', 'уй', 'ил', 'ыл',
  'им', 'ым', 'ен', 'ят', 'ит', 'ыт', 'ую', 'ю',
];

const _noun = [
  'иями', 'ями', 'ами', 'иях', 'ией', 'ими', 'ыми', 'иям', 'ием', 'ах',
  'ях', 'ам', 'ям', 'ом', 'ем', 'ов', 'ев', 'ие', 'ье', 'еи', 'ии', 'ей',
  'ой', 'ий', 'ию', 'ью', 'ия', 'ья', 'а', 'е', 'и', 'й', 'о', 'у', 'ы',
  'ь', 'ю', 'я',
];

const _superlative = ['ейше', 'ейш'];
const _derivational = ['ость', 'ост'];

/// Приводит русское слово к основе.
///
/// Слова короче трёх букв и слова без кириллицы возвращаются без изменений —
/// стеммить их бессмысленно и только вредит точности.
String stemRussian(String input) {
  var word = input.toLowerCase().replaceAll('ё', 'е');
  if (word.length < 3) return word;

  // RV — область после первой гласной. Все правила шагов 1, 2 и 4 действуют
  // только в ней, иначе стеммер съедает корень коротких слов.
  var rv = -1;
  for (var i = 0; i < word.length; i++) {
    if (_isVowel(word[i])) {
      rv = i + 1;
      break;
    }
  }
  if (rv < 0) return word;

  // R1 — после первой пары «гласная + согласная»; R2 — то же внутри R1.
  var r1 = word.length;
  for (var i = 1; i < word.length; i++) {
    if (!_isVowel(word[i]) && _isVowel(word[i - 1])) {
      r1 = i + 1;
      break;
    }
  }
  var r2 = word.length;
  for (var i = r1 + 1; i < word.length; i++) {
    if (!_isVowel(word[i]) && _isVowel(word[i - 1])) {
      r2 = i + 1;
      break;
    }
  }

  /// Снимает первое подходящее окончание из [endings], если оно целиком лежит
  /// в области, начинающейся с [region]. Для группы 1 окончание обязано идти
  /// после «а» или «я» — это отличает деепричастия от похожих форм.
  String? tryRemove(List<String> endings, int region, {bool afterAYa = false}) {
    for (final e in endings) {
      if (!word.endsWith(e)) continue;
      final cut = word.length - e.length;
      if (cut < region) continue;
      if (afterAYa) {
        if (cut == 0) continue;
        final prev = word[cut - 1];
        if (prev != 'а' && prev != 'я') continue;
      }
      return word.substring(0, cut);
    }
    return null;
  }

  // --- Шаг 1 ---
  var step1 = tryRemove(_perfectiveGerund1, rv, afterAYa: true) ??
      tryRemove(_perfectiveGerund2, rv);

  if (step1 != null) {
    word = step1;
  } else {
    final refl = tryRemove(_reflexive, rv);
    if (refl != null) word = refl;

    // Причастие снимается только вместе с прилагательным окончанием:
    // «читающего» → «читающ» → «чита».
    final adj = tryRemove(_adjective, rv);
    if (adj != null) {
      word = adj;
      final part = tryRemove(_participle1, rv, afterAYa: true) ??
          tryRemove(_participle2, rv);
      if (part != null) word = part;
    } else {
      final verb = tryRemove(_verb1, rv, afterAYa: true) ??
          tryRemove(_verb2, rv);
      if (verb != null) {
        word = verb;
      } else {
        final noun = tryRemove(_noun, rv);
        if (noun != null) word = noun;
      }
    }
  }

  // --- Шаг 2: снять «и» ---
  if (word.length > rv && word.endsWith('и')) {
    word = word.substring(0, word.length - 1);
  }

  // --- Шаг 3: словообразовательный суффикс в R2 ---
  final deriv = tryRemove(_derivational, r2);
  if (deriv != null) word = deriv;

  // --- Шаг 4 ---
  if (word.endsWith('нн')) {
    word = word.substring(0, word.length - 1);
  } else {
    final sup = tryRemove(_superlative, rv);
    if (sup != null) {
      word = sup;
      if (word.endsWith('нн')) word = word.substring(0, word.length - 1);
    } else if (word.length > rv && word.endsWith('ь')) {
      word = word.substring(0, word.length - 1);
    }
  }

  return word;
}

/// Лёгкий стеммер для английского: снимает только словоизменительные
/// окончания. Полный Porter здесь избыточен — для библейского текста важнее
/// не «перестемить» имена собственные вроде `Moses` или `Jesus`.
String stemEnglish(String input) {
  var w = input.toLowerCase();
  if (w.length < 4) return w;
  for (final e in const ['ies', 'ied']) {
    if (w.endsWith(e) && w.length > 4) return '${w.substring(0, w.length - 3)}y';
  }
  for (final e in const ['sses', 'shes', 'ches', 'xes']) {
    if (w.endsWith(e)) return w.substring(0, w.length - 2);
  }
  if (w.endsWith('ing') && w.length > 5) return w.substring(0, w.length - 3);
  if (w.endsWith('ed') && w.length > 4) return w.substring(0, w.length - 2);
  if (w.endsWith('s') && !w.endsWith('ss') && !w.endsWith('us')) {
    return w.substring(0, w.length - 1);
  }
  return w;
}

/// Убирает беглую гласную «о»/«е» перед конечной согласной основы.
///
/// Snowball этого не умеет, и из-за этого рассыпается целый класс частотных
/// русских слов: любовь→«любов», но любви→«любв»; день→«ден», но дня→«дн».
/// Без такой нормализации поиск по «любовь» молча не находит «любви».
///
/// Приведение огрубляющее и иногда склеивает разные слова (бог/бег → «бг»),
/// поэтому такие формы индексируются ОТДЕЛЬНОЙ колонкой с меньшим весом:
/// точное совпадение основы всегда ранжируется выше.
String reduceFleeting(String stem) {
  var s = stem;
  // Область RV у Snowball начинается после первой гласной, поэтому у совсем
  // коротких слов окончание не снимается вовсе: «дня» так и остаётся «дня»,
  // тогда как «день» даёт «ден». Дотягиваем этот случай вручную.
  if (s.length <= 3 && s.isNotEmpty && _isVowel(s[s.length - 1])) {
    s = s.substring(0, s.length - 1);
  }
  if (s.length < 3) return s;
  final last = s.length - 1;
  final v = s[last - 1];
  if ((v == 'о' || v == 'е') && !_isVowel(s[last]) && !_isVowel(s[last - 2])) {
    return s.substring(0, last - 1) + s[last];
  }
  return s;
}

final _wordSplit = RegExp(r"[^\p{L}\p{N}́]+", unicode: true);

final _cyrillic = RegExp(r'[а-яёА-ЯЁ]');

/// Разбивает текст на слова и приводит каждое к основе.
/// Язык определяется по самому слову, а не по переводу: в русском тексте
/// встречаются латинские вкрапления, и наоборот.
List<String> tokenizeAndStem(String text) {
  final out = <String>[];
  for (final raw in text.split(_wordSplit)) {
    if (raw.isEmpty) continue;
    final w = raw.replaceAll('́', ''); // ударение
    if (w.isEmpty) continue;
    out.add(_cyrillic.hasMatch(w) ? stemRussian(w) : stemEnglish(w));
  }
  return out;
}

/// Огрублённые формы для второй колонки индекса. Возвращает столько же
/// позиций, сколько [tokenizeAndStem], чтобы поиск по фразе не сбивался.
List<String> tokenizeReduced(String text) =>
    tokenizeAndStem(text).map(reduceFleeting).toList();

/// Слово вместе с его границами в исходной строке.
typedef Token = ({String word, String stem, int start, int end});

final _wordRe = RegExp(r'[\p{L}\p{N}]+', unicode: true);

/// Разбивает текст на слова, сохраняя смещения.
///
/// Нужен и для привязки сущностей (по каким символам рисовать нажимаемую
/// область), и для подсветки найденного в результатах поиска. Смещения
/// считаются по той же строке `verses.text`, что и спаны Стронга.
List<Token> tokenizeWithOffsets(String text) {
  final out = <Token>[];
  for (final m in _wordRe.allMatches(text)) {
    final w = m.group(0)!;
    final stem = _cyrillic.hasMatch(w) ? stemRussian(w) : stemEnglish(w);
    out.add((word: w, stem: stem, start: m.start, end: m.end));
  }
  return out;
}

/// Заглавная ли первая буква. Для русского это сильный признак имени
/// собственного, но только не в начале предложения.
bool startsUpper(String w) =>
    w.isNotEmpty && w[0].toUpperCase() == w[0] && w[0].toLowerCase() != w[0];
