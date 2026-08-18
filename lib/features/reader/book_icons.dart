/// Иконка для каждой книги.
///
/// Знак рядом с названием нужен не для красоты: в сетке из 39 книг Ветхого
/// Завета глаз цепляется за форму быстрее, чем читает подпись, и «Авд» от
/// «Агг» отличается мгновенно.
///
/// Берём системный набор Material, а не рисуем свой: иконки уже вшиты во
/// Flutter, не тянут ни шрифтов, ни сети и одинаково выглядят на обеих
/// платформах. Где точного символа нет, стоит ближайший по смыслу — лев у
/// Даниила, весы правосудия у Судей, письмо у посланий.
library;

import 'package:flutter/material.dart';

const _icons = <String, IconData>{
  // ── Пятикнижие и исторические книги ──
  'GEN': Icons.eco_outlined, // лист — начало творения
  'EXO': Icons.festival_outlined, // шатёр — скиния в пустыне
  'LEV': Icons.receipt_long_outlined, // свиток закона
  'NUM': Icons.format_list_numbered_rounded, // перепись народа
  'DEU': Icons.menu_book_outlined, // повторение закона
  'JOS': Icons.flag_outlined, // взятие земли
  'JDG': Icons.gavel_rounded, // судьи
  'RUT': Icons.grass_outlined, // жатва на поле Вооза
  '1SA': Icons.emoji_events_outlined, // царства
  '2SA': Icons.emoji_events_outlined,
  '1KI': Icons.emoji_events_outlined,
  '2KI': Icons.emoji_events_outlined,
  '1CH': Icons.import_contacts_outlined, // летописи
  '2CH': Icons.import_contacts_outlined,
  'EZR': Icons.history_edu_outlined, // книжник с пером
  'NEH': Icons.foundation_outlined, // восстановление стен
  'EST': Icons.star_border_rounded,
  'JOB': Icons.person_outline_rounded,

  // ── Учительные ──
  'PSA': Icons.music_note_outlined,
  'PRO': Icons.lightbulb_outline_rounded,
  'ECC': Icons.hourglass_empty_rounded, // суета и время
  'SNG': Icons.favorite_border_rounded,

  // ── Пророки ──
  'ISA': Icons.record_voice_over_outlined,
  'JER': Icons.record_voice_over_outlined,
  'LAM': Icons.water_drop_outlined, // плач
  'EZK': Icons.trip_origin_rounded, // колесо видения
  'DAN': Icons.pets_rounded, // ров со львами
  'HOS': Icons.volunteer_activism_outlined, // верность вопреки
  'JOL': Icons.bug_report_outlined, // нашествие саранчи
  'AMO': Icons.campaign_outlined,
  'OBA': Icons.local_fire_department_outlined,
  'JON': Icons.set_meal_outlined, // большая рыба
  'MIC': Icons.terrain_rounded,
  'NAM': Icons.location_city_outlined, // суд над Ниневией
  'HAB': Icons.visibility_outlined, // пророк на страже
  'ZEP': Icons.wb_twilight_rounded, // день Господень
  'HAG': Icons.account_balance_outlined, // восстановление храма
  'ZEC': Icons.auto_awesome_outlined, // ночные видения
  'MAL': Icons.mark_email_unread_outlined, // «вестник»

  // ── Евангелия и Деяния ──
  'MAT': Icons.account_tree_outlined, // родословие
  'MRK': Icons.bolt_outlined, // «тотчас» — самое быстрое Евангелие
  'LUK': Icons.medical_services_outlined, // Лука-врач
  'JHN': Icons.light_mode_outlined, // свет и Слово
  'ACT': Icons.groups_outlined, // рождение Церкви

  // ── Послания ──
  'ROM': Icons.mail_outline_rounded,
  '1CO': Icons.mail_outline_rounded,
  '2CO': Icons.mail_outline_rounded,
  'GAL': Icons.mail_outline_rounded,
  'EPH': Icons.mail_outline_rounded,
  'PHP': Icons.mail_outline_rounded,
  'COL': Icons.mail_outline_rounded,
  '1TH': Icons.mail_outline_rounded,
  '2TH': Icons.mail_outline_rounded,
  '1TI': Icons.drafts_outlined, // письма ученикам
  '2TI': Icons.drafts_outlined,
  'TIT': Icons.drafts_outlined,
  'PHM': Icons.drafts_outlined,
  'HEB': Icons.church_outlined, // священство и жертва
  'JAS': Icons.handshake_outlined, // вера в делах
  '1PE': Icons.sailing_outlined, // рыбак
  '2PE': Icons.sailing_outlined,
  '1JN': Icons.favorite_border_rounded, // «Бог есть любовь»
  '2JN': Icons.favorite_border_rounded,
  '3JN': Icons.favorite_border_rounded,
  'JUD': Icons.shield_outlined, // «подвизаться за веру»
  'REV': Icons.brightness_7_outlined, // откровение
};

IconData bookIcon(String bookId) =>
    _icons[bookId.toUpperCase()] ?? Icons.menu_book_outlined;
