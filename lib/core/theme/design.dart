/// Единые размеры и повторяющиеся элементы интерфейса.
///
/// До этого файла в коде жили восемь разных скруглений, три ширины полей и
/// десяток кеглей — каждый экран решал за себя. Здесь один набор правил, и
/// экраны берут размеры отсюда, а не выдумывают свои.
///
/// Шрифты разделены по роли: Literata — только текст Писания и заголовки, всё
/// служебное набирается Inter. Интерфейс должен исчезать, а текст оставаться.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import 'reading_theme.dart';

/// Отступы.
abstract final class Insets {
  /// Поля экрана. Одно значение на всё приложение.
  static const screen = 20.0;

  /// Внутри карточки.
  static const card = 16.0;

  /// Между соседними карточками.
  static const gap = 10.0;

  /// Между разделами экрана.
  static const section = 26.0;
}

/// Скругления.
abstract final class Radii {
  static const chip = 12.0;
  static const card = 16.0;
  static const sheet = 24.0;
}

/// Шрифтовая шкала интерфейса.
abstract final class AppText {
  /// Заголовок карточки или страницы — набирается Literata, как и Писание.
  static TextStyle heading(ReadingColors c, {double size = 19}) => TextStyle(
        fontFamily: 'Literata',
        fontSize: size,
        fontWeight: FontWeight.w600,
        height: 1.25,
        color: c.text,
      );

  static TextStyle body(ReadingColors c) => TextStyle(
        fontFamily: 'Inter',
        fontSize: 14,
        height: 1.5,
        color: c.muted,
      );

  static TextStyle strong(ReadingColors c) => TextStyle(
        fontFamily: 'Inter',
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: c.text,
      );

  static TextStyle caption(ReadingColors c) => TextStyle(
        fontFamily: 'Inter',
        fontSize: 12,
        height: 1.45,
        color: c.faint,
      );

  /// Ссылка-действие внутри карточки.
  static TextStyle action(ReadingColors c) => TextStyle(
        fontFamily: 'Inter',
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: c.accent,
      );
}

/// Заголовок раздела: «ГДЕ ВСТРЕЧАЕТСЯ», «ЧЕЛОВЕК ДНЯ».
class SectionTitle extends ConsumerWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(settingsProvider).colors;
    final label = Text(
      text.toUpperCase(),
      style: TextStyle(
        fontFamily: 'Inter',
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.9,
        color: c.faint,
      ),
    );
    if (trailing == null) return label;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [label, trailing!],
    );
  }
}

/// Карточка: поверхность с тонкой рамкой вместо тени.
///
/// Тень на светлой теме превращается в грязь, а на тёмной не видна вовсе.
/// Рамка в один пиксель одинаково честно работает в обеих.
class AppCard extends ConsumerWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(Insets.card),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(settingsProvider).colors;
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(Radii.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.card),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.card),
            border: Border.all(color: c.divider),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Кнопка-переключатель: фильтры, выбор перевода, разделы «Моё».
class AppChip extends ConsumerWidget {
  const AppChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final int? count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(settingsProvider).colors;
    return Material(
      color: selected ? c.accent : c.surface,
      borderRadius: BorderRadius.circular(Radii.chip),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.chip),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.chip),
            border: Border.all(color: selected ? c.accent : c.divider),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon,
                      size: 16,
                      color: selected ? Colors.white : c.muted),
                  const SizedBox(width: 6),
                ],
                Text(
                  count == null ? label : '$label · $count',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : c.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Строка длинного списка: заголовок, пояснение и стрелка.
///
/// Списки на сотни строк карточками не делаются — они превращаются в лестницу.
/// Здесь обычная строка с разделителем, отбитым от края текста.
class AppRow extends ConsumerWidget {
  const AppRow({
    super.key,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
    this.titleFont = 'Literata',
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;
  final String titleFont;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(settingsProvider).colors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                        fontFamily: titleFont,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                        color: c.text,
                      )),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body(c).copyWith(fontSize: 13)),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 10), trailing!],
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child:
                  Icon(Icons.chevron_right_rounded, size: 18, color: c.faint),
            ),
          ],
        ),
      ),
    );
  }
}

/// Разделитель списка, отбитый от левого края.
class AppDivider extends ConsumerWidget {
  const AppDivider({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Divider(
        height: 1,
        thickness: 1,
        color: ref.watch(settingsProvider).colors.divider,
      );
}
