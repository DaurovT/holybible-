/// Оболочка приложения и нижняя навигация.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/reading_theme.dart';
import 'features/explore/explore_screen.dart';
import 'features/library/library_screen.dart';
import 'features/reader/reader_screen.dart';
import 'features/today/today_screen.dart';
import 'state/providers.dart';

/// Разделы, наполнение которых придёт с бэкенда позже, скрыты флагом.
/// Показывать заведомо пустые вкладки нельзя: App Store отклоняет сборки с
/// «placeholder content» по правилу 2.1.
const showUnreleasedSections =
    bool.fromEnvironment('SHOW_UNRELEASED', defaultValue: false);

class BibleApp extends ConsumerWidget {
  const BibleApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return MaterialApp(
      title: 'Библия',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(settings),
      home: const _Shell(),
    );
  }
}

/// Нижняя навигация.
///
/// Своя, а не стандартная: у системной под выбранной вкладкой рисуется крупная
/// плашка, которая в спокойном оформлении читалки выглядит чужеродно. Здесь
/// хватает цвета и насыщенности подписи.
class _BottomBar extends ConsumerWidget {
  const _BottomBar({required this.index});

  final int index;

  static const _tabs = [
    (Icons.menu_book_outlined, Icons.menu_book_rounded, 'Читать'),
    (Icons.today_outlined, Icons.today_rounded, 'Сегодня'),
    (Icons.explore_outlined, Icons.explore_rounded, 'Исследовать'),
    (Icons.bookmark_border_rounded, Icons.bookmark_rounded, 'Моё'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(settingsProvider).colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.divider)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 54,
          child: Row(
            children: [
              for (var i = 0; i < _tabs.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => ref.read(tabProvider.notifier).state = i,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          i == index ? _tabs[i].$2 : _tabs[i].$1,
                          size: 22,
                          color: i == index ? c.accent : c.muted,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _tabs[i].$3,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 11,
                            fontWeight:
                                i == index ? FontWeight.w600 : FontWeight.w500,
                            color: i == index ? c.accent : c.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Shell extends ConsumerWidget {
  const _Shell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(settingsProvider).colors;
    final dbAsync = ref.watch(bibleDbProvider);
    final index = ref.watch(tabProvider);

    return dbAsync.when(
      loading: () => Scaffold(
        backgroundColor: c.background,
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => Scaffold(
        backgroundColor: c.background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(30),
            child: Text('Не удалось открыть текст.\n$e',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Inter', color: c.muted)),
          ),
        ),
      ),
      data: (_) => Scaffold(
        backgroundColor: c.background,
        // IndexedStack, а не переключение экранов: читалка держит позицию
        // прокрутки, и уходить из неё на другую вкладку нельзя ценой потери
        // места, на котором человек остановился.
        body: IndexedStack(
          index: index,
          children: const [
            ReaderScreen(),
            TodayScreen(),
            ExploreScreen(),
            LibraryScreen(),
          ],
        ),
        bottomNavigationBar: _BottomBar(index: index),
      ),
    );
  }
}
