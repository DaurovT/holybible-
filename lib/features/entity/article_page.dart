/// Статья глоссария: предмет, понятие или обычай.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/design.dart';
import '../../data/article_repository.dart';
import '../../state/providers.dart';

class ArticlePage extends ConsumerWidget {
  const ArticlePage({super.key, required this.articleId});
  final int articleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final c = s.colors;
    final db = ref.watch(bibleDbProvider).valueOrNull;
    final article = db?.articleById(articleId);

    if (article == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(title: Text(article.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            Insets.screen, 8, Insets.screen, 60),
        children: [
          Text(article.title, style: AppText.heading(c, size: 30)),
          const SizedBox(height: 18),
          Text(
            article.text,
            style: TextStyle(
                fontFamily: s.fontFamily,
                fontSize: s.fontSize * 0.94,
                height: 1.65,
                color: c.text),
          ),
          const SizedBox(height: 20),
          Text(
            'Источник: Библейская энциклопедия архимандрита Никифора (1891). '
            'Текст в общественном достоянии, получен из Викитеки.',
            style: AppText.caption(c).copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}
