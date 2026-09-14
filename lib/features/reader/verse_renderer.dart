/// Превращение главы в блоки для отрисовки.
///
/// Стих сам по себе не единица вёрстки: в прозе несколько стихов идут одним
/// абзацем, а в поэзии один стих разбит на несколько строк. Поэтому сначала
/// собираем блоки (абзац или строка), а уже потом рисуем.
library;

import 'package:flutter/material.dart';
// RenderParagraph нужен, чтобы по координате пальца определить символ под ним:
// именно так тап попадает в конкретное слово без recognizer'а на каждом спане.
import 'package:flutter/rendering.dart';

import '../../core/theme/reading_theme.dart';
import '../../data/models.dart';

/// Кусок текста, относящийся к одному стиху внутри блока.
class BlockPiece {
  final Verse verse;
  final VerseSegment segment;

  /// Показывать ли номер стиха перед этим куском. Номер ставится только у
  /// первого сегмента стиха: иначе в поэзии он повторится на каждой строке.
  final bool showNumber;

  const BlockPiece(this.verse, this.segment, this.showNumber);
}

class ReaderBlock {
  final ParagraphStyle style;
  final List<BlockPiece> pieces;

  /// Заголовок раздела, стоящий перед блоком.
  final String? heading;
  final int headingLevel;

  const ReaderBlock({
    required this.style,
    required this.pieces,
    this.heading,
    this.headingLevel = 1,
  });

  int get firstVerseNumber =>
      pieces.isEmpty ? 0 : pieces.first.verse.number;
}

/// Раскладывает главу на блоки.
List<ReaderBlock> buildBlocks(Chapter chapter, {required bool paragraphMode}) {
  final headings = <int, Heading>{
    for (final h in chapter.headings) h.beforeVerse: h
  };

  final blocks = <ReaderBlock>[];
  ParagraphStyle? style;
  var pieces = <BlockPiece>[];
  String? pendingHeading;
  var pendingLevel = 1;

  void flush() {
    if (pieces.isEmpty) return;
    blocks.add(ReaderBlock(
      style: style ?? ParagraphStyle.prose,
      pieces: pieces,
      heading: pendingHeading,
      headingLevel: pendingLevel,
    ));
    pieces = [];
    pendingHeading = null;
  }

  for (final verse in chapter.verses) {
    final h = headings[verse.number];
    if (h != null) {
      flush();
      pendingHeading = h.text;
      pendingLevel = h.level;
    }

    for (var i = 0; i < verse.segments.length; i++) {
      final seg = verse.segments[i];
      // В режиме «каждый стих с новой строки» разрыв ставим всегда.
      final breaks = seg.breaksLine || (!paragraphMode && i == 0);
      if (breaks || style != seg.style) {
        flush();
        style = seg.style;
      }
      pieces.add(BlockPiece(verse, seg, i == 0));
    }
  }
  flush();
  return blocks;
}

/// Абзац или строка текста Писания.
///
/// Тап обрабатывается не через recognizer на каждом слове, а попаданием в
/// сущность по спанам: recognizer'ов на главу набегали бы сотни, и каждый
/// требует ручного освобождения.
class ReaderParagraph extends StatefulWidget {
  const ReaderParagraph({
    super.key,
    required this.block,
    required this.settings,
    required this.selectedVerses,
    this.chapterNumber,
    this.highlights = const {},
    this.notedVerses = const {},
    this.focusedVerses = const {},
    this.onTapEntity,
    this.onTapVerse,
    this.onLongPressVerse,
    this.onTapFootnote,
    this.onTapNote,
  });

  final ReaderBlock block;
  final ReadingSettings settings;
  final Set<int> selectedVerses;

  /// Номер главы, если абзац — первый в ней. Цифра встаёт в начало текста, а
  /// не отдельной строкой над ним: так делают печатные издания, и так глава не
  /// съедает пол-экрана перед первым словом.
  final int? chapterNumber;

  /// Цвет выделения по ключу стиха.
  final Map<int, HighlightTint> highlights;

  /// Ключи стихов, к которым есть заметка: рядом с номером встаёт метка.
  final Set<int> notedVerses;

  /// Ключи стихов, к которым только что перешли. Подсветка временная — она
  /// говорит «вот он», а не «ты это выделил».
  final Set<int> focusedVerses;

  final void Function(String entityId)? onTapEntity;
  final void Function(Verse verse)? onTapVerse;
  final void Function(Verse verse)? onLongPressVerse;
  final void Function(String note)? onTapFootnote;
  final void Function(Verse verse)? onTapNote;

  @override
  State<ReaderParagraph> createState() => _ReaderParagraphState();
}

/// Что находится под конкретным диапазоном символов собранного абзаца.
class _Hit {
  const _Hit({
    required this.start,
    required this.end,
    required this.verse,
    this.entityId,
    this.note,
    this.isNoteMarker = false,
  });

  final int start;
  final int end;
  final Verse verse;
  final String? entityId;
  final String? note;
  final bool isNoteMarker;
}

class _ReaderParagraphState extends State<ReaderParagraph> {
  /// Карта «диапазон символов в собранном абзаце → что там находится».
  /// Заполняется при построении спанов и используется для попадания тапом.
  final List<_Hit> _hits = [];

  final _textKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    final c = s.colors;
    final span = _buildSpan(context);

    final indent = switch (widget.block.style) {
      ParagraphStyle.poetry1 => 18.0,
      ParagraphStyle.poetry2 => 38.0,
      ParagraphStyle.poetry3 => 58.0,
      ParagraphStyle.listItem => 24.0,
      ParagraphStyle.indented => 24.0,
      _ => 0.0,
    };
    final isPoetry = widget.block.style.isPoetry;

    return Padding(
      padding: EdgeInsets.only(
        left: indent,
        top: isPoetry ? 2 : 10,
        bottom: isPoetry ? 2 : 0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.block.heading != null)
            Padding(
              padding: EdgeInsets.only(
                  top: widget.block.headingLevel == 0 ? 34 : 26, bottom: 10),
              child: Text(
                widget.block.heading!,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: s.fontSize * 0.82,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                  color: c.muted,
                ),
              ),
            ),
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapUp: _handleTap,
            onLongPressStart: _handleLongPress,
            child: Text.rich(
              span,
              key: _textKey,
              textAlign: widget.block.style == ParagraphStyle.psalmTitle
                  ? TextAlign.left
                  : TextAlign.start,
            ),
          ),
        ],
      ),
    );
  }

  TextSpan _buildSpan(BuildContext context) {
    _hits.clear();
    final s = widget.settings;
    final c = s.colors;
    var offset = 0;

    final baseStyle = TextStyle(
      fontFamily: s.fontFamily,
      fontSize: s.fontSize,
      height: s.lineHeight,
      color: c.text,
      fontStyle: widget.block.style == ParagraphStyle.psalmTitle
          ? FontStyle.italic
          : FontStyle.normal,
    );

    final children = <InlineSpan>[];

    // Последний выведенный символ. Разделитель между стихами и текст самого
    // стиха приходят из разных мест, и без этого следа в абзаце появляются
    // двойные пробелы, а строка может начаться с отбивки.
    var lastChar = '';

    if (widget.chapterNumber != null) {
      final label = '${widget.chapterNumber} ';
      children.add(TextSpan(
        text: label,
        style: baseStyle.copyWith(
          fontSize: s.fontSize * 1.45,
          fontWeight: FontWeight.w600,
          height: 1.0,
        ),
      ));
      offset += label.length;
      lastChar = ' ';
    }

    for (var pi = 0; pi < widget.block.pieces.length; pi++) {
      final piece = widget.block.pieces[pi];
      final verse = piece.verse;
      final selected = widget.selectedVerses.contains(verse.number);
      final tint = widget.highlights[verse.vkey];

      if (pi > 0 && lastChar.isNotEmpty && lastChar != ' ') {
        children.add(const TextSpan(text: ' '));
        offset += 1;
        lastChar = ' ';
      }

      if (piece.showNumber && s.showVerseNumbers) {
        final label = '${verse.number} ';
        children.add(TextSpan(
          text: label,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: s.fontSize * 0.62,
            height: s.lineHeight,
            color: c.verseNumber,
            fontFeatures: const [FontFeature.superscripts()],
          ),
        ));
        _hits.add(_Hit(
          start: offset,
          end: offset + label.length,
          verse: verse,
        ));
        offset += label.length;
        lastChar = ' ';
      }

      // Метка заметки. Иначе заметка живёт только в разделе «Моё», и человек
      // перечитывает отрывок, не зная, что сам уже что-то о нём написал.
      if (piece.showNumber && widget.notedVerses.contains(verse.vkey)) {
        children.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Icon(Icons.sticky_note_2_outlined,
                size: s.fontSize * 0.62, color: c.accent),
          ),
        ));
        // WidgetSpan занимает ровно один символ-заполнитель, и попадание
        // пальцем считается по нему же.
        _hits.add(_Hit(
          start: offset,
          end: offset + 1,
          verse: verse,
          isNoteMarker: true,
        ));
        offset += 1;
        lastChar = ' ';
      }

      for (final run in piece.segment.runs) {
        if (run.isNote) {
          if (!s.showFootnotes || run.noteText == null) continue;
          const marker = '*';
          children.add(TextSpan(
            text: marker,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: s.fontSize * 0.7,
              height: s.lineHeight,
              color: c.accent,
              fontFeatures: const [FontFeature.superscripts()],
            ),
          ));
          _hits.add(_Hit(
            start: offset,
            end: offset + marker.length,
            verse: verse,
            note: run.noteText,
          ));
          offset += marker.length;
          continue;
        }

        // Внутри run'а текст режется на части по сущностям, чтобы у них было
        // собственное оформление.
        final pieces = _splitByMentions(verse, run.start, run.end);
        for (final part in pieces) {
          var text = verse.text.substring(part.start, part.end);
          // Разделитель между сегментами стиха лежит внутри его смещений.
          // Если пробел уже выведен, второй не нужен.
          if (lastChar.isEmpty || lastChar == ' ') text = text.trimLeft();
          if (text.isEmpty) continue;
          // Выбор пальцем главнее краски: пока отрывок выделен, он должен
          // читаться как выделенный, даже если стих раскрашен.
          final background = selected || widget.focusedVerses.contains(verse.vkey)
              ? c.highlight
              : tint?.on(c);
          final style = _styleFor(run, part.entityId != null, selected, s, c)
              .merge(baseStyle.copyWith(
                  color: _colorFor(run, verse, part.start, s, c),
                  backgroundColor: background));

          children.add(TextSpan(text: text, style: style));
          _hits.add(_Hit(
            start: offset,
            end: offset + text.length,
            verse: verse,
            entityId: part.entityId,
          ));
          offset += text.length;
          lastChar = text.substring(text.length - 1);
        }
      }
    }

    return TextSpan(style: baseStyle, children: children);
  }

  Color _colorFor(
      TextRun run, Verse verse, int at, ReadingSettings s, ReadingColors c) {
    if (!s.showWordsOfJesus) return c.text;
    // Своя разметка перевода — если она есть.
    if (run.isWordsOfJesus) return c.wordsOfJesus;
    // Перенесённая граница: всё от неё и до конца стиха — прямая речь.
    final from = verse.wjFrom;
    if (from != null && at >= from) return c.wordsOfJesus;
    return c.text;
  }

  TextStyle _styleFor(TextRun run, bool isEntity, bool selected,
      ReadingSettings s, ReadingColors c) {
    var style = const TextStyle();
    if (run.isSupplied) {
      style = style.copyWith(fontStyle: FontStyle.italic);
    }
    if (run.isDivineName) {
      style = style.copyWith(
          fontFeatures: const [FontFeature.enable('smcp')],
          letterSpacing: 0.4);
    }
    if (isEntity && s.entityHints != EntityHintLevel.none) {
      // Не синяя ссылка, а пунктир в цвете самого текста: подсказка есть,
      // но глаз за неё не цепляется и строка не рябит.
      style = style.copyWith(
        decoration: TextDecoration.underline,
        decorationStyle: TextDecorationStyle.dotted,
        decorationColor: c.text.withValues(
            alpha: s.entityHints == EntityHintLevel.subtle ? 0.22 : 0.45),
        decorationThickness: 1.0,
      );
    }
    return style;
  }

  /// Режет диапазон run'а на части так, чтобы каждое упоминание сущности
  /// оказалось отдельным куском.
  List<({int start, int end, String? entityId})> _splitByMentions(
      Verse verse, int start, int end) {
    final relevant = [
      for (final m in verse.mentions)
        if (m.end > start && m.start < end && m.confidence >= 0.2) m
    ];
    if (relevant.isEmpty) {
      return [(start: start, end: end, entityId: null)];
    }
    final out = <({int start, int end, String? entityId})>[];
    var cursor = start;
    for (final m in relevant) {
      final b = m.end > end ? end : m.end;
      // Упоминания могут пересекаться: одно и то же имя иногда привязано к
      // двум личностям. Что бы ни лежало в базе, текст не должен выводиться
      // дважды — курсор идёт только вперёд.
      if (b <= cursor) continue;
      final a = m.start < cursor ? cursor : m.start;
      if (a > cursor) out.add((start: cursor, end: a, entityId: null));
      out.add((start: a, end: b, entityId: m.entityId));
      cursor = b;
    }
    if (cursor < end) out.add((start: cursor, end: end, entityId: null));
    return out;
  }

  /// Находит, во что попал палец, через позицию символа в отрисованном тексте.
  _Hit? _hitAt(Offset globalPosition) {
    final box = _textKey.currentContext?.findRenderObject();
    if (box is! RenderBox) return null;
    final local = box.globalToLocal(globalPosition);
    final para = _findParagraph(box);
    if (para == null) return null;
    final pos = para.getPositionForOffset(local);
    for (final h in _hits) {
      if (pos.offset >= h.start && pos.offset < h.end) return h;
    }
    return null;
  }

  RenderParagraph? _findParagraph(RenderObject o) {
    if (o is RenderParagraph) return o;
    RenderParagraph? found;
    o.visitChildren((child) {
      found ??= _findParagraph(child);
    });
    return found;
  }

  void _handleTap(TapUpDetails d) {
    final hit = _hitAt(d.globalPosition);
    if (hit == null) return;
    if (hit.isNoteMarker) {
      widget.onTapNote?.call(hit.verse);
      return;
    }
    if (hit.note != null) {
      widget.onTapFootnote?.call(hit.note!);
      return;
    }
    if (hit.entityId != null) {
      widget.onTapEntity?.call(hit.entityId!);
      return;
    }
    widget.onTapVerse?.call(hit.verse);
  }

  void _handleLongPress(LongPressStartDetails d) {
    final hit = _hitAt(d.globalPosition);
    if (hit == null) return;
    widget.onLongPressVerse?.call(hit.verse);
  }
}
