/// Редактор заметки к отрывку.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/design.dart';

import '../../data/models.dart';
import '../../data/user_database.dart';
import '../../state/providers.dart';
import '../../state/user_data.dart';

Future<void> showNoteSheet(
  BuildContext context, {
  required List<Verse> verses,
  required String reference,
  Note? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _NoteSheet(
      verses: verses,
      reference: reference,
      existing: existing,
    ),
  );
}

class _NoteSheet extends ConsumerStatefulWidget {
  const _NoteSheet({
    required this.verses,
    required this.reference,
    this.existing,
  });

  final List<Verse> verses;
  final String reference;
  final Note? existing;

  @override
  ConsumerState<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends ConsumerState<_NoteSheet> {
  late final _controller =
      TextEditingController(text: widget.existing?.body ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final body = _controller.text.trim();
    final notifier = ref.read(userDataProvider.notifier);
    // Пустая заметка — это её удаление: так человек стирает текст и закрывает
    // экран, не разыскивая отдельную кнопку.
    if (body.isEmpty) {
      if (widget.existing != null) await notifier.removeNote(widget.existing!.id);
    } else {
      await notifier.saveNote(
        id: widget.existing?.id,
        verses: widget.verses,
        body: body,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(settingsProvider).colors;
    final quote = widget.verses.map((v) => v.text).join(' ');

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            Insets.screen, 18, Insets.screen, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.reference,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.text,
                    ),
                  ),
                ),
                if (widget.existing != null)
                  IconButton(
                    tooltip: 'Удалить заметку',
                    icon: Icon(Icons.delete_outline_rounded,
                        size: 20, color: c.muted),
                    onPressed: () async {
                      await ref
                          .read(userDataProvider.notifier)
                          .removeNote(widget.existing!.id);
                      if (context.mounted) Navigator.of(context).pop();
                    },
                  ),
              ],
            ),
            if (quote.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                quote,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Literata',
                  fontSize: 14,
                  height: 1.5,
                  fontStyle: FontStyle.italic,
                  color: c.muted,
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 8,
              minLines: 4,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(
                  fontFamily: 'Inter', fontSize: 15, height: 1.5, color: c.text),
              decoration: InputDecoration(
                hintText: 'Что вы об этом думаете',
                hintStyle: TextStyle(fontFamily: 'Inter', color: c.faint),
                filled: true,
                fillColor: c.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Radii.chip),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: c.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11)),
                ),
                onPressed: _save,
                child: const Text('Готово',
                    style: TextStyle(
                        fontFamily: 'Inter', fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
