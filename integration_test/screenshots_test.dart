/// Скриншоты для App Store.
///
/// Проходит по приложению так же, как человек: нажимает на слово в тексте, на
/// стих, открывает карточки. Кадры складываются в docs/screenshots/ в размере
/// экрана симулятора — для iPhone 17 Pro Max это требуемые App Store 1320×2868.
/// Кадры приходят с альфа-каналом, а App Store Connect такие не принимает, —
/// после съёмки их сплющивает `python3 tool/flatten_screenshots.py`.
///
///     xcrun simctl boot "iPhone 17 Pro Max"
///     flutter drive -d "iPhone 17 Pro Max" \
///       --driver=test_driver/integration_test.dart \
///       --target=integration_test/screenshots_test.dart \
///       --dart-define=AI_ENDPOINT=https://holybible-api.eastus.cloudapp.azure.com
///
/// Адрес сервера нужен только затем, чтобы на панели отрывка были видны кнопки
/// разбора: без него они скрыты. Сам разбор на симуляторе не работает — там нет
/// App Attest, — поэтому кадра с ответом ИИ здесь нет, его снимают на телефоне.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holy_bible/app.dart';
import 'package:holy_bible/core/theme/reading_theme.dart';
import 'package:holy_bible/features/entity/entity_page.dart';
import 'package:holy_bible/features/map/bible_map.dart';
import 'package:holy_bible/state/providers.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('скриншоты для App Store', (tester) async {
    // Открываемся на Нагорной проповеди, в светлой палитре, с православным
    // календарём — чтобы съёмка не зависела от того, что осталось с прошлого
    // запуска.
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await prefs.setString('pos_book', 'MAT');
    await prefs.setInt('pos_chapter', 5);

    await tester.pumpWidget(const ProviderScope(child: BibleApp()));
    // Первый запуск распаковывает базу — это секунды.
    await _waitFor(tester, find.textContaining('нищие', findRichText: true),
        timeout: const Duration(minutes: 3));
    await _settle(tester);

    final container =
        ProviderScope.containerOf(tester.element(find.byType(BibleApp)));

    // На Android снимок берётся только с поверхности-изображения, её включают
    // один раз заранее. Кадры Android кладутся отдельно: для Google Play свои
    // размеры, и затирать ими скриншоты App Store нельзя.
    if (Platform.isAndroid) {
      await binding.convertFlutterSurfaceToImage();
      await _settle(tester);
    }
    final prefix = Platform.isAndroid ? 'android/' : '';

    Future<void> shot(String name) async {
      await _settle(tester);
      await binding.takeScreenshot('$prefix$name');
    }

    // 1. Отрывок выделен — на панели кнопки разбора.
    await _tapWord(tester, 'нищие');
    // На Android разбора нет (App Attest только у Apple) — ждём панель по
    // соседней кнопке.
    await _waitFor(
        tester, find.text(Platform.isIOS ? 'Объяснить' : 'Параллельные места'));
    await shot('01-razbor');

    // 2. Слова оригинала к тому же стиху.
    await tester.ensureVisible(find.text('Слова оригинала'));
    await _settle(tester);
    await tester.tap(find.text('Слова оригинала'));
    await _pause(tester, seconds: 8); // словарь Стронга распаковывается лениво
    await shot('07-original');
    _navigator(tester).pop();
    await _settle(tester);
    await tester.tap(find.byIcon(Icons.close_rounded).last);
    await _settle(tester);

    // 3. «Кто это?» — нажатие на имя в родословии.
    container.read(jumpRequestProvider.notifier).state =
        (bookId: 'MAT', chapter: 1, vkey: null);
    await _waitFor(tester, find.textContaining('родил Исаака', findRichText: true));
    await _pause(tester, seconds: 5); // пока не погаснет подсветка перехода
    await _tapWord(tester, 'Авраам', after: 'Сына ');
    await _pause(tester, seconds: 2);
    await shot('02-kto-eto');
    _navigator(tester).pop();
    await _settle(tester);

    // 4. Место на карте.
    container.read(tabProvider.notifier).state = 2;
    await _settle(tester);
    await tester.enterText(find.byType(TextField), 'Иерусалим');
    await _settle(tester);
    await tester.tap(find
        .descendant(of: find.byType(ListView), matching: find.text('Иерусалим'))
        .first);
    // Карту чуть ниже верха: заголовок «Где это» стоит прямо над ней, а обрывок
    // статьи уходит из кадра.
    await _scrollPageTo(tester, binding, find.byType(BibleMap), 0.1, 'karta');
    await shot('03-karta');
    _navigator(tester).pop();
    await _settle(tester);

    // 5. Карточка человека: родство и упоминания.
    await tester.enterText(find.byType(TextField), 'Давид');
    await _settle(tester);
    await tester.tap(find
        .descendant(of: find.byType(ListView), matching: find.text('Давид'))
        .first);
    // Статья о Давиде длинная; в кадр — родство, ради которого карточка и есть.
    await _scrollPageTo(tester, binding, find.text('СВЯЗИ'), 0.015, 'svyazi');
    await shot('04-svyazi');
    _navigator(tester).pop();
    await _settle(tester);

    // 6. «Сегодня»: праздник, человек дня, календарь.
    container.read(tabProvider.notifier).state = 1;
    await _pause(tester, seconds: 2);
    await shot('06-segodnya');

    // 7. Чтение в тёмной палитре.
    final settings = container.read(settingsProvider.notifier);
    settings.update(
        container.read(settingsProvider).copyWith(palette: ReadingPalette.dark));
    container.read(jumpRequestProvider.notifier).state =
        // Синодальная нумерация: «Господь — Пастырь мой» здесь 22-й псалом.
        (bookId: 'PSA', chapter: 22, vkey: null);
    container.read(tabProvider.notifier).state = 0;
    await _pause(tester, seconds: 6);
    await shot('05-noch');

    settings.update(container
        .read(settingsProvider)
        .copyWith(palette: ReadingPalette.light));
    await _settle(tester);
  });
}

/// Листает открытую карточку до [target] и ставит его на [alignment] высоты.
///
/// Разделы карточки догружаются асинхронно, и раскладка сдвигается уже после
/// первого кадра: найденный виджет успевал выпасть из ленивого списка до
/// следующего шага. Поэтому сначала ждём, пока страница уляжется, а выравниваем
/// сразу после прокрутки. Если всё же не вышло — оставляем отладочный кадр и
/// список текстов на экране.
Future<void> _scrollPageTo(WidgetTester tester,
    IntegrationTestWidgetsFlutterBinding binding, Finder target,
    double alignment, String name) async {
  await _waitFor(tester, find.byType(EntityPage));
  await _pause(tester, seconds: 3);
  try {
    await tester.scrollUntilVisible(target, 300,
        scrollable: find
            .descendant(
                of: find.byType(EntityPage), matching: find.byType(Scrollable))
            .first);
    await Scrollable.ensureVisible(tester.element(target.first),
        alignment: alignment);
  } catch (_) {
    await binding.takeScreenshot('debug-$name');
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .take(40);
    debugPrint('на экране: ${texts.join(' | ')}');
    rethrow;
  }
}

NavigatorState _navigator(WidgetTester tester) =>
    tester.state<NavigatorState>(find.byType(Navigator).first);

/// Кадры идут вживую: даём анимациям доиграть, прокачивая кадры по-настоящему.
Future<void> _settle(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }
}

Future<void> _pause(WidgetTester tester, {required int seconds}) =>
    _settle(tester, frames: seconds * 1000 ~/ 80);

Future<void> _waitFor(WidgetTester tester, Finder finder,
    {Duration timeout = const Duration(seconds: 30)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  throw TestFailure('не дождались: $finder');
}

/// Нажимает на слово в тексте Писания так же, как палец: находит его место в
/// отрисованном абзаце и тапает в середину. [after] уточняет, какое из
/// вхождений нужно, если слово встречается раньше.
Future<void> _tapWord(WidgetTester tester, String word, {String after = ''}) async {
  final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  for (final para in tester.renderObjectList<RenderParagraph>(find.byType(RichText))) {
    if (!para.attached) continue;
    final text = para.text.toPlainText();
    final at = text.indexOf('$after$word');
    if (at < 0) continue;
    final start = at + after.length;
    final boxes = para.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: start + word.length));
    if (boxes.isEmpty) continue;
    final center = para.localToGlobal(boxes.first.toRect().center);
    if (center.dy < 80 || center.dy > screen.height - 120) continue;
    await tester.tapAt(center);
    await _settle(tester);
    return;
  }
  throw TestFailure('слово «$word» не видно на экране');
}
