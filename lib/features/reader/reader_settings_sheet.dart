/// Настройки оформления текста.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/design.dart';
import '../../core/theme/reading_theme.dart';
import '../../state/providers.dart';

void showReaderSettings(BuildContext context, WidgetRef ref) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    // Без ограничения панель разворачивается во весь экран и заезжает под
    // часы: настроек много, а список внутри растёт по содержимому.
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.85,
    ),
    builder: (_) => const _SettingsSheet(),
  );
}

class _SettingsSheet extends ConsumerWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final c = s.colors;
    final translations = ref.watch(translationsProvider).valueOrNull ?? const [];
    final current = ref.watch(translationProvider);
    final parallel = ref.watch(parallelTranslationProvider);

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.sheet)),
      ),
      child: SafeArea(
        top: false,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(
              Insets.screen, 12, Insets.screen, 24),
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                    color: c.divider, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),

            SectionTitle('Перевод'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final t in translations)
                  AppChip(
                    label: t.abbrev,
                    selected: t.id == current,
                    onTap: () {
                      ref.read(translationProvider.notifier).set(t.id);
                      // Один и тот же перевод в двух колонках смысла не имеет.
                      if (ref.read(parallelTranslationProvider) == t.id) {
                        ref.read(parallelTranslationProvider.notifier).set(null);
                      }
                    },
                  ),
              ],
            ),
            const SizedBox(height: 22),

            SectionTitle('Второй перевод рядом'),
            const SizedBox(height: 4),
            Text(
              'Стихи встают парами: в этом режиме абзацы не собираются, '
              'иначе переводы не выровнять построчно.',
              style:
                  TextStyle(fontFamily: 'Inter', fontSize: 12, color: c.faint),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                AppChip(
                  label: 'Нет',
                  selected: parallel == null,
                  onTap: () =>
                      ref.read(parallelTranslationProvider.notifier).set(null),
                ),
                for (final t in translations)
                  if (t.id != current)
                    AppChip(
                      label: t.abbrev,
                      selected: parallel == t.id,
                      onTap: () => ref
                          .read(parallelTranslationProvider.notifier)
                          .set(t.id),
                    ),
              ],
            ),
            const SizedBox(height: 22),

            SectionTitle('Движение по тексту'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final l in ReaderLayout.values)
                  AppChip(
                    label: l.title,
                    selected: s.layout == l,
                    onTap: () => n.update(s.copyWith(layout: l)),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(s.layout.hint, style: AppText.caption(c)),
            const SizedBox(height: 22),

            SectionTitle('Оформление'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final p in ReadingPalette.values)
                  AppChip(
                    label: p.title,
                    selected: s.palette == p,
                    onTap: () => n.update(s.copyWith(palette: p)),
                  ),
              ],
            ),
            const SizedBox(height: 22),

            SectionTitle('Размер текста'),
            Slider(
              value: s.fontSize,
              min: 14,
              max: 28,
              divisions: 14,
              activeColor: c.accent,
              label: s.fontSize.round().toString(),
              onChanged: (v) => n.update(s.copyWith(fontSize: v)),
            ),

            SectionTitle('Межстрочный интервал'),
            Slider(
              value: s.lineHeightScale,
              min: 0.85,
              max: 1.3,
              divisions: 9,
              activeColor: c.accent,
              onChanged: (v) => n.update(s.copyWith(lineHeightScale: v)),
            ),
            const SizedBox(height: 8),

            _Switch(
              title: 'Абзацами',
              subtitle: 'Стихи текут сплошным текстом, как в книге',
              value: s.paragraphMode,
              onChanged: (v) => n.update(s.copyWith(paragraphMode: v)),
            ),
            _Switch(
              title: 'Номера стихов',
              value: s.showVerseNumbers,
              onChanged: (v) => n.update(s.copyWith(showVerseNumbers: v)),
            ),
            _Switch(
              title: 'Слова Христа цветом',
              subtitle: 'В Синодальном издании такой разметки нет — границы '
                  'перенесены из английского. Речь посреди стиха не '
                  'выделяется: лучше не покрасить, чем покрасить чужое',
              value: s.showWordsOfJesus,
              onChanged: (v) => n.update(s.copyWith(showWordsOfJesus: v)),
            ),
            _Switch(
              title: 'Сноски',
              value: s.showFootnotes,
              onChanged: (v) => n.update(s.copyWith(showFootnotes: v)),
            ),

            const SizedBox(height: 14),
            SectionTitle('Подсказки о людях и местах'),
            const SizedBox(height: 4),
            Text(
              'Насколько заметно помечать слова, за которыми есть карточка. '
              'Нажатие работает в любом случае.',
              style:
                  TextStyle(fontFamily: 'Inter', fontSize: 12, color: c.faint),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                for (final h in EntityHintLevel.values)
                  AppChip(
                    label: h.title,
                    selected: s.entityHints == h,
                    onTap: () => n.update(s.copyWith(entityHints: h)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}



class _Switch extends ConsumerWidget {
  const _Switch({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(settingsProvider).colors;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      activeThumbColor: c.accent,
      title: Text(title,
          style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: c.text)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!,
              style: TextStyle(
                  fontFamily: 'Inter', fontSize: 12, color: c.faint)),
      value: value,
      onChanged: onChanged,
    );
  }
}
