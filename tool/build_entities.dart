/// Достраивает bible.db слоем сущностей: люди, места, понятия, их связи,
/// статьи и — главное — спаны упоминаний в тексте каждого перевода.
///
/// Спаны считаются здесь, на сборке, а не в приложении: распознавание имён во
/// время чтения было бы медленным, требовало бы сети и не работало офлайн.
/// В рантайме тап по слову превращается в один индексный запрос.
///
/// Запуск: dart run tool/build_entities.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'align_names.dart';
import 'tipnr_parser.dart';

/// Порог доверия к привязке. Ниже него слово не становится нажимаемым:
/// ложная подсветка раздражает сильнее, чем её отсутствие.
const minCoverage = 0.25;
const minSpecificity = 0.15;

/// Имена, которые не берутся ни текстом, ни словарём.
///
/// Иисуса Навина Синодальный зовёт просто «Иисусом», и по частоте слово
/// достаётся Христу; фараон пишется со строчной и потому не считается именем
/// вовсе. Таких случаев немного, и все они на виду — это самые упоминаемые
/// люди и места без русского имени.
const ruNameOverrides = {
  // Иуду в Синодальном чаще называют по колену и стране — «Иудея», и слово
  // достаётся человеку. То же с Господом: чаще прочих в его стихах стоит
  // «Саваоф».
  'Judah@Gen.29.35-Rev': 'Иуда',
  'LORD@Gen.1.1-Rev': 'Господь',
  // Отдельной статьи об апостоле в энциклопедии нет — есть «Петр апостол и
  // его послания», а слово «Петра» занято городом.
  'Peter@Mat.4.18-2Pe': 'Пётр',
  'Canaan@Gen.10.18-Act': 'Ханаан',
  // Здесь текст почти всегда говорит о наделе, народе или празднике —
  // «в колене Гадовом», «сынов Дановых», «есть пасху», — и начальной формы
  // имени в стихах этой сущности не встречается вовсе.
  'Passover@Exo.12.11-Heb': 'Пасха',
  'Gad@Gen.30.11-Rev': 'Гад',
  'Dan@Gen.14.14-Amo': 'Дан',
  'Syria@Jdg.10.6-Gal': 'Сирия',
  'Amorites@Gen.10.16-Amo': 'Аморреи',
  'Baal@Num.25.3-Rom': 'Ваал',
  'Gibeah@Jos.18.28-Hos': 'Гива',
  'Gentiles@Gen.10.5-Rev': 'Язычники',
  'Levi@Gen.29.34-Rev': 'Левиты',
  'Joshua@Exo.17.9-Heb': 'Иисус Навин',
  'Pharaoh@Exo.3.10-Rom': 'Фараон',
  'Pharaoh@Gen.37.36-Act': 'Фараон',
  'Pharaoh@Exo.1.11-Heb': 'Фараон',
  'Hophra@Jer.37.5-Ezk': 'Вафрий',
  'Selah@Psa.3.2-Hab': 'Села',
  'Maskil@Psa.32.1-': 'Маскил',
  'Judea@Ezr.9.9-1Th': 'Иудея',
  'Negeb@Gen.12.9-Zec': 'Негев',
  'Shephelah@Deu.1.7-Zec': 'Шефела',
  'Arabah@Deu.1.1-Zec': 'Арава',
  'Nile@Gen.41.1-Zec': 'Нил',
  'Holy_Place@Exo.26.33-Heb': 'Святилище',
  'Most_Holy_Place@1Ki.6.16-Heb': 'Святое святых',
  'Great_Sea@Exo.23.31-Ezk': 'Великое море',
  'Brook_of_Egypt@Num.34.5-Ezk': 'Поток Египетский',
  'Moab_Plains@Num.22.1-Jos': 'Равнины Моава',
  'Hor_Mount@Num.20.22-Deu': 'Гора Ор',
  'James@Mat.4.21-Act': 'Иаков Зеведеев',
  'James@Mat.13.55-Jud': 'Иаков, брат Господень',
  'Joseph@Mat.1.16-Jhn': 'Иосиф Обручник',
  'Philip@Act.6.5-': 'Филипп благовестник',
  'Tiberius@Mat.22.17-Jhn': 'Тиверий',
  'Claudius@Act.11.28-': 'Клавдий',
  'Herod@Act.12.1-': 'Ирод Агриппа',
  'Jeroboam@2Ki.13.13-Amo': 'Иеровоам',
  'Greece@Isa.66.19-Act': 'Греция',
  'Canaan@Gen.9.18-1Ch': 'Ханаан',
  'Hagri@1Ch.5.10-Psa': 'Агаряне',
  // Имена, которых нет ни в тексте (Синодальный зовёт их иначе), ни в
  // словаре — по написанию их не угадать: Gath и «Геф», Nun и «Навин».
  'Gath@Jos.11.22-Mic': 'Геф',
  'Nebuzaradan@2Ki.25.8-Jer': 'Навузардан',
  'Molech@Lev.18.21-Act': 'Молох',
  'Chinnereth@Num.34.11-Jhn': 'Киннереф',
  'Kiriathaim@Gen.14.5-Amo': 'Кириафаим',
  'Elizabeth@Luk.1.5-': 'Елисавета',
  'Zechariah@1Ch.9.21-': 'Захария',
  'Beth-aven@Jos.7.2-Hos': 'Беф-Авен',
  'Engedi@Gen.14.7-Ezk': 'Ен-Геди',
  'Herodias@Mat.14.3-Luk': 'Иродиада',
  'Jonathan@2Sa.15.27-1Ki': 'Ионафан',
  'Nathanael@Jhn.1.45-': 'Нафанаил',
  'Beth-arabah@Jos.15.6-1Ch': 'Беф-Арава',
  'Nathan@2Sa.5.14-Luk': 'Нафан',
  'Nadab@1Ki.14.20-': 'Надав',
  'Zadok@1Ch.6.12-Neh': 'Садок',
  'Elealeh@Num.32.3-Jer': 'Елеале',
  'Adoram@2Sa.20.24-2Ch': 'Адорам',
  'Pharaoh@2Ki.18.21-Isa': 'Фараон',
  'Pharaoh@Gen.12.15-': 'Фараон',
  'Esau_Mount@Oba.1.8-': 'Гора Исава',
  'House_of_the_Forest@1Ki.7.2-Isa': 'Дом из Ливанского дерева',
  'Preparation_Festival@Mat.27.62-Jhn': 'День приготовления',
  'Miktam@Psa.16.1-': 'Миктам',
  'East@Jdg.6.3-Ezk': 'Восток',
};

/// Русские имена в начальной форме — заголовки энциклопедии Никифора.
///
/// Имя из текста приходит в том падеже, в каком оно чаще стоит в стихе:
/// «Израиля», «Иордана», «Ханаанской». Заголовок энциклопедии — то же имя в
/// синодальном написании и в именительном падеже, поэтому словоформу снимаем
/// по нему. Файл тот же, из которого потом собираются статьи; если его нет,
/// имя остаётся текстовой словоформой — сборка сущностей от энциклопедии не
/// зависит.
class RussianNames {
  RussianNames(this.byNorm, this.titles, this.byKey);

  final Map<String, String> byNorm;
  final List<String> titles;

  /// Заголовки по первым четырём буквам — чтобы найти словарное имя для
  /// словоформы, которой в словаре нет: «Ассирию» → «Ассирия».
  final Map<String, List<String>> byKey;

  static RussianNames load(String root) {
    final f = File('$root/data/raw/nikifor/articles.json');
    if (!f.existsSync()) return RussianNames({}, [], {});
    final raw = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    final names = <String>[];
    for (final key in raw.keys) {
      var name = key.startsWith('БЭАН/') ? key.substring(5) : key;
      // «АВИЯ, 1» и «ААРОН (просветлённый)» — уточнения в заголовке.
      name = name.replaceAll(RegExp(r'\s*\([^)]*\)'), '').split(',').first.trim();
      if (name.isEmpty || !RegExp('^[А-ЯЁ]').hasMatch(name)) continue;
      names.add(name);
    }

    final byNorm = <String, String>{};
    for (final n in names) {
      if (!n.contains(' ')) byNorm[normalizeName(n)] = n;
    }
    // Первое слово составных заголовков («Иеремии плач», «Субботний путь»)
    // в словарь не берём: оно само чаще всего стоит не в именительном падеже,
    // а имя сущности после этого застывает в нём же.
    final byKey = <String, List<String>>{};
    for (final t in byNorm.values) {
      if (t.contains(' ')) continue;
      (byKey[nameKey(t)] ??= []).add(t);
    }
    return RussianNames(byNorm, byNorm.values.toList(), byKey);
  }

  /// Начальная форма среди найденных в тексте словоформ. Если ни одна не
  /// нашлась в словаре, берём самую короткую: у имён падежи только удлиняют
  /// слово («Давид» → «Давида», «Иордан» → «Иордана»).
  String nominative(NameMatch m) {
    // Словоформы группируем по основе. Разные основы — это разные слова:
    // падежи имени («Ассирию», «Ассирии»), прилагательное от него
    // («Ассирийского») и случайно попавшее в те же стихи чужое имя
    // («Пасхор» в стихах о пасхе, «Гадорам» в наделе Гада).
    final weight = <String, int>{};
    for (final e in m.formCounts.entries) {
      weight.update(stemOf(e.key), (v) => v + e.value, ifAbsent: () => e.value);
    }

    /// Имена словаря с этой же основой: они и стоят в именительном падеже.
    List<String> dictionary(String stem) => [
          for (final t in byKey[nameKey(stem)] ?? const <String>[])
            if (stemOf(t) == stem) t
        ];

    // Основу выбираем ту, которую знает словарь, — даже если чаще в тексте
    // стоит прилагательное. Без словаря остаётся самая частая.
    String? base;
    var best = -1;
    for (final e in weight.entries) {
      if (dictionary(e.key).isNotEmpty && e.value > best) {
        best = e.value;
        base = e.key;
      }
    }
    base ??= weight.entries.reduce((a, b) => a.value >= b.value ? a : b).key;

    final common = {
      for (final e in m.formCounts.entries)
        if (stemOf(e.key) == base) e.key: e.value
    };
    if (common.isEmpty) return m.surface;

    // Если сам текст где-то ставит имя в начальной форме — а словарь это
    // подтверждает, — берём её.
    final known = [
      for (final f in common.keys)
        if (byNorm.containsKey(normalizeName(f))) f
    ]..sort((a, b) => common[b]!.compareTo(common[a]!));
    if (known.isNotEmpty) return byNorm[normalizeName(known.first)]!;

    // Иначе — словарное имя, ближайшее по написанию к тому, что стоит в
    // тексте: с одной основой в словаре соседствуют «Иеремия» и «Иеремай».
    final named = dictionary(base);
    if (named.isNotEmpty) {
      final frequent = normalizeName(
          common.entries.reduce((a, b) => a.value >= b.value ? a : b).key);
      named.sort((a, b) => editDistance(normalizeName(a), frequent)
          .compareTo(editDistance(normalizeName(b), frequent)));
      return named.first;
    }

    // Совсем без словаря: самая короткая словоформа ближе прочих к начальной.
    final forms = common.keys.toList()
      ..sort((a, b) {
        final byLength = a.length.compareTo(b.length);
        return byLength != 0
            ? byLength
            : m.formCounts[b]!.compareTo(m.formCounts[a]!);
      });
    // Понятия в Синодальном пишутся со строчной («пасха», «фарисеи»), но в
    // списке рядом со словарными именами такая строка выглядит недоделанной.
    final name = forms.first;
    return name[0].toUpperCase() + name.substring(1);
  }

  /// Имя для сущности, которой в русском тексте слова не нашлось: ищем
  /// заголовок, который читается так же, как английское имя. Той же мерой
  /// похожести подтверждаются и обычные привязки, только здесь она остаётся
  /// единственным доводом — поэтому порог высокий, а второй кандидат должен
  /// заметно отставать, иначе легко перепутать Иоаса с Иосией.
  String? guess(String englishName) {
    var best = 0.0, second = 0.0;
    String? bestTitle;
    for (final t in titles) {
      final s = translitSimilarity(t, englishName);
      if (s > best) {
        second = best;
        best = s;
        bestTitle = t;
      } else if (s > second) {
        second = s;
      }
    }
    return (best >= 0.85 && best - second >= 0.07) ? bestTitle : null;
  }
}

/// Основа имени: слово без падежного окончания. У русских имён меняется
/// только хвост, и меняется он на гласную, «ь» или «й» — «Израиль»,
/// «Израиля», «Израилю» дают одно «израил». Прилагательные («Ассирийского»)
/// основы не сохраняют, поэтому от них имя не восстанавливается.
String stemOf(String s) {
  var w = normalizeName(s);
  while (w.isNotEmpty && 'аеиоуыэюяьй'.contains(w[w.length - 1])) {
    w = w.substring(0, w.length - 1);
  }
  return w;
}

String normalizeName(String s) {
  final b = StringBuffer();
  for (final ch in s.toLowerCase().replaceAll('ё', 'е').split('')) {
    if (RegExp(r'[а-я]').hasMatch(ch)) b.write(ch);
  }
  return b.toString();
}

/// Английское имя из TIPNR бывает не именем, а перечнем разночтений:
/// «Nile =ESV,NIV; canals,streams,river =NIV; …». В интерфейсе такая строка
/// выглядит поломкой, поэтому оставляем первое написание.
String cleanEnglishName(String raw) {
  var s = raw.split(RegExp(r'\s*=')).first;
  s = s.split(RegExp(r'[;,/]')).first;
  return s.trim().isEmpty ? raw.trim() : s.trim();
}

const entitySchema = '''
CREATE TABLE entities (
  id         TEXT PRIMARY KEY,
  kind       TEXT NOT NULL,          -- person | place | other
  name_ru    TEXT,
  name_en    TEXT,
  gender     TEXT,
  tribe      TEXT,
  geo_area   TEXT,
  openbible  TEXT,
  lat        REAL,
  lon        REAL,
  modern     TEXT,
  place_type TEXT,
  image_url  TEXT,
  strong     TEXT,
  original   TEXT,
  descr      TEXT,
  briefest   TEXT,
  brief      TEXT,
  short      TEXT,
  article    TEXT,
  ref_count  INTEGER NOT NULL DEFAULT 0,
  first_vkey INTEGER
);

-- Граф связей. rel: parent | sibling | partner | child | founder | inhabitant
CREATE TABLE entity_rel (
  entity_id TEXT NOT NULL,
  rel       TEXT NOT NULL,
  other_id  TEXT NOT NULL
);

-- Все места, где сущность упоминается, даже если имя в стихе не найдено
-- (местоимение, перифраз). Это список «Все упоминания» в карточке.
CREATE TABLE entity_refs (
  entity_id TEXT NOT NULL,
  vkey      INTEGER NOT NULL
);

-- Нажимаемые области в тексте.
CREATE TABLE mentions (
  verse_id   INTEGER NOT NULL,
  start      INTEGER NOT NULL,
  finish     INTEGER NOT NULL,
  entity_id  TEXT NOT NULL,
  confidence REAL NOT NULL
);
''';

const entityIndexes = '''
CREATE INDEX idx_rel_entity ON entity_rel(entity_id);
CREATE INDEX idx_rel_other ON entity_rel(other_id);
CREATE INDEX idx_refs_entity ON entity_refs(entity_id);
CREATE INDEX idx_refs_vkey ON entity_refs(vkey);
CREATE INDEX idx_mentions_verse ON mentions(verse_id);
CREATE INDEX idx_mentions_entity ON mentions(entity_id);
CREATE INDEX idx_entities_kind ON entities(kind, ref_count DESC);
''';

void main() {
  final root = Directory.current.path;
  final db = sqlite3.open('$root/assets/db/bible.db');

  for (final t in ['mentions', 'entity_refs', 'entity_rel', 'entities']) {
    db.execute('DROP TABLE IF EXISTS $t');
  }
  db.execute('DROP TABLE IF EXISTS entity_fts');
  db.execute(entitySchema);
  db.execute('''
    CREATE VIRTUAL TABLE entity_fts USING fts5(
      name_ru, name_en, brief,
      content='', tokenize="unicode61 remove_diacritics 0"
    );
  ''');

  final ruNames = RussianNames.load(root);
  stdout.writeln('русских имён в словаре: ${ruNames.titles.length}');

  stdout.writeln('читаю TIPNR…');
  final entities = parseTipnr(File('$root/data/raw/tipnr.txt').readAsStringSync());
  final byId = {for (final e in entities) e.id: e};
  stdout.writeln('  сущностей: ${entities.length}');

  final geo = (jsonDecode(
          File('$root/data/derived/places_geo.json').readAsStringSync())
      as Map<String, dynamic>);

  // Ключи географии — идентификаторы TIPNR вида «Jerusalem@Jos.10.1», а у наших
  // сущностей в идентификаторе стоит диапазон: «Jerusalem@Gen.14.18-Rev».
  // Совпадали только места с единственной ссылкой, поэтому у Иерусалима
  // координат не было, а были они у 386 безвестных урочищ. Ищем по имени.
  String nameOf(String id) {
    final at = id.indexOf('@');
    return at < 0 ? id : id.substring(0, at);
  }

  final geoByName = <String, Map<String, dynamic>>{};
  for (final e in geo.entries) {
    geoByName.putIfAbsent(nameOf(e.key), () => e.value as Map<String, dynamic>);
  }
  stdout.writeln('  мест с координатами: ${geo.length} '
      '(имён: ${geoByName.length})');

  // Тексты и внутренние идентификаторы стихов по каждому переводу.
  final texts = <String, Map<int, String>>{};
  final verseIds = <String, Map<int, int>>{};
  for (final tr in ['syn', 'web']) {
    final m = <int, String>{};
    final ids = <int, int>{};
    for (final r in db.select(
        'SELECT id, vkey, text FROM verses WHERE translation_id = ?', [tr])) {
      final k = r['vkey'] as int;
      m[k] = r['text'] as String;
      ids[k] = r['id'] as int;
    }
    texts[tr] = m;
    verseIds[tr] = ids;
  }

  stdout.writeln('считаю частоты имён…');
  // Две таблицы частот: для имён собственных считаем только слова с
  // заглавной буквы, для нарицательных понятий — все.
  final df = {
    for (final tr in texts.keys) tr: buildKeyFrequency(texts[tr]!.values)
  };
  final dfAll = {
    for (final tr in texts.keys)
      tr: buildKeyFrequency(texts[tr]!.values, onlyCapitalized: false)
  };

  final insEntity = db.prepare('''
    INSERT INTO entities(id,kind,name_ru,name_en,gender,tribe,geo_area,
      openbible,lat,lon,modern,place_type,image_url,strong,original,descr,
      briefest,brief,short,article,ref_count,first_vkey)
    VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
  ''');
  final insRel =
      db.prepare('INSERT INTO entity_rel(entity_id,rel,other_id) VALUES(?,?,?)');
  final insRef =
      db.prepare('INSERT INTO entity_refs(entity_id,vkey) VALUES(?,?)');
  final insMention = db.prepare(
      'INSERT INTO mentions(verse_id,start,finish,entity_id,confidence) '
      'VALUES(?,?,?,?,?)');
  final insFts = db.prepare(
      'INSERT INTO entity_fts(rowid,name_ru,name_en,brief) VALUES(?,?,?,?)');

  db.execute('BEGIN');
  var rowid = 0;
  var mentionCount = 0;

  /// Упоминания по стихам — копим, чтобы потом снять пересечения. Писать сразу
  /// нельзя: конкуренты за одно и то же слово находятся в разных сущностях.
  final pending =
      <int, List<({int start, int end, String id, double conf})>>{};
  var namedRu = 0, namedEn = 0, snapped = 0, guessed = 0;
  final unmatched = <String>[];

  for (final e in entities) {
    rowid++;
    final refs = e.allRefs.toList()..sort();

    // Имя ищем отдельно в каждом переводе: словоформы и даже само написание
    // различаются (Пётр/Peter, Сион/Zion).
    final upper = e.kind != EntityKind.other;
    final matches = <String, NameMatch?>{};
    for (final tr in ['syn', 'web']) {
      final mine = {
        for (final k in refs)
          if (texts[tr]!.containsKey(k)) k: texts[tr]![k]!
      };
      final found = findNames(
          verses: mine,
          df: (upper ? df : dfAll)[tr]!,
          englishName: e.englishName,
          limit: 2,
          requireUpper: upper);
      final best = found.isEmpty ? null : found.first;
      matches[tr] = (best != null &&
              best.coverage >= minCoverage &&
              best.specificity >= minSpecificity)
          ? best
          : null;
    }

    final ru = matches['syn'];
    final en = matches['web'];
    if (en != null) namedEn++;

    // Русское имя: перекрытие вручную, затем начальная форма найденного в
    // тексте слова, затем догадка по словарю для тех, кому в Синодальном
    // слова не нашлось вовсе. Английское имя посреди русского списка читается
    // как поломка, поэтому доходим до него в последнюю очередь.
    var nameRu = ruNameOverrides[e.id];
    if (nameRu == null && ru != null) {
      nameRu = ruNames.nominative(ru);
      snapped += (nameRu == ru.surface) ? 0 : 1;
    }
    if (nameRu == null) {
      nameRu = ruNames.guess(cleanEnglishName(e.englishName));
      if (nameRu != null) guessed++;
    }
    if (nameRu != null) namedRu++;
    if (ru == null && en == null) unmatched.add(e.id);

    final g = (geo[e.id] ?? geoByName[nameOf(e.id)])
        as Map<String, dynamic>?;

    insEntity.execute([
      e.id,
      e.kind.name,
      nameRu,
      cleanEnglishName(en?.surface ?? e.englishName),
      e.gender.isEmpty ? null : e.gender,
      e.tribe.isEmpty ? null : e.tribe,
      e.geoArea.isEmpty ? null : e.geoArea,
      e.openBibleName.isEmpty ? null : e.openBibleName,
      g?['lat'],
      g?['lon'],
      g?['modern'],
      g?['types'],
      g?['thumb'],
      e.primaryStrong.isEmpty ? null : e.primaryStrong,
      e.original.isEmpty ? null : e.original,
      e.description.isEmpty ? null : e.description,
      e.briefest.isEmpty ? null : e.briefest,
      e.brief.isEmpty ? null : e.brief,
      e.short.isEmpty ? null : e.short,
      e.article.isEmpty ? null : e.article,
      refs.length,
      refs.isEmpty ? null : refs.first,
    ]);
    // В поиске нужны все словоформы: человек ищет «Иордана», а имя теперь
    // хранится как «Иордан».
    insFts.execute([
      rowid,
      [nameRu ?? '', ...?ru?.forms].join(' '),
      cleanEnglishName(en?.surface ?? e.englishName),
      e.brief
    ]);

    for (final v in refs) {
      insRef.execute([e.id, v]);
    }

    void rels(List<String> list, String rel) {
      for (final other in list) {
        if (byId.containsKey(other)) insRel.execute([e.id, rel, other]);
      }
    }

    rels(e.parents, 'parent');
    rels(e.siblings, 'sibling');
    rels(e.partners, 'partner');
    rels(e.offspring, 'child');
    rels(e.founders, 'founder');
    rels(e.inhabitants, 'inhabitant');

    for (final tr in ['syn', 'web']) {
      final m = matches[tr];
      if (m == null) continue;
      final conf = m.coverage * m.specificity;
      for (final o in m.occurrences) {
        final vid = verseIds[tr]![o.vkey];
        if (vid == null) continue;
        (pending[vid] ??= [])
            .add((start: o.start, end: o.end, id: e.id, conf: conf));
      }
    }
  }

  // Одно слово — одна сущность. В родословии Матфея «Наассона» досталось и
  // Наассону, и Аминадаву: в первоисточнике они стоят в одном стихе, и
  // выравнивание не смогло их развести. Оставляем самого уверенного кандидата —
  // подсветка, ведущая не туда, раздражает сильнее, чем её отсутствие.
  var dropped = 0;
  for (final entry in pending.entries) {
    final list = entry.value
      ..sort((a, b) {
        final byConf = b.conf.compareTo(a.conf);
        if (byConf != 0) return byConf;
        final byLength = (b.end - b.start).compareTo(a.end - a.start);
        return byLength != 0 ? byLength : a.start.compareTo(b.start);
      });
    final taken = <({int start, int end})>[];
    for (final m in list) {
      if (taken.any((t) => m.start < t.end && m.end > t.start)) {
        dropped++;
        continue;
      }
      taken.add((start: m.start, end: m.end));
      insMention.execute([entry.key, m.start, m.end, m.id, m.conf]);
      mentionCount++;
    }
  }
  db.execute('COMMIT');

  db.execute(entityIndexes);
  db.execute("INSERT INTO entity_fts(entity_fts) VALUES('optimize')");
  db.execute('VACUUM');

  stdout.writeln('\n── итог ──');
  stdout.writeln('сущностей:        ${entities.length}');
  stdout.writeln('с русским именем: $namedRu '
      '(${(namedRu * 100 / entities.length).toStringAsFixed(0)}%)');
  stdout.writeln('  приведено к начальной форме: $snapped');
  stdout.writeln('  найдено по словарю:          $guessed');
  stdout.writeln('с англ. именем:   $namedEn '
      '(${(namedEn * 100 / entities.length).toStringAsFixed(0)}%)');
  stdout.writeln('без привязки:     ${unmatched.length}');
  stdout.writeln('спанов упоминаний: $mentionCount');
  stdout.writeln('снято пересечений: $dropped');

  final rel = db.select('SELECT COUNT(*) c FROM entity_rel').first['c'];
  stdout.writeln('связей в графе:   $rel');

  stdout.writeln('\nпримеры без привязки: ${unmatched.take(8).join(', ')}');

  _sample(db);
  db.dispose();

  final mb = (File('$root/assets/db/bible.db').lengthSync() / 1024 / 1024)
      .toStringAsFixed(1);
  stdout.writeln('\nbible.db — $mb МБ');
}

/// Показывает, как это будет выглядеть в приложении: берём конкретный стих и
/// перечисляем нажимаемые слова.
void _sample(Database db) {
  for (final ref in [
    ('syn', 'JHN', 3, 1),
    ('syn', 'LEV', 1, 1),
    ('syn', 'MAT', 27, 2),
  ]) {
    final (tr, book, ch, v) = ref;
    final row = db.select(
        'SELECT id, text FROM verses WHERE translation_id=? AND book_id=? '
        'AND chapter=? AND verse=?',
        [tr, book, ch, v]);
    if (row.isEmpty) continue;
    final id = row.first['id'] as int;
    final text = row.first['text'] as String;
    stdout.writeln('\n$book $ch:$v — $text');
    for (final m in db.select('''
        SELECT m.start, m.finish, m.confidence, e.id, e.kind, e.name_ru, e.briefest
        FROM mentions m JOIN entities e ON e.id = m.entity_id
        WHERE m.verse_id = ? ORDER BY m.start''', [id])) {
      final word = text.substring(m['start'] as int, m['finish'] as int);
      stdout.writeln('   «$word» → ${m['id']} [${m['kind']}] '
          '${m['briefest'] ?? ''} '
          '(${(m['confidence'] as double).toStringAsFixed(2)})');
    }
  }
}
