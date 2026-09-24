/// The collections sheet: lists the smart shelves and the user's
/// collections, either to add the acting book into one (opened from
/// the detail page) or to filter the home shelf (opened from the
/// header). The new-collection form state is local to the sheet.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:grimoire_example/src/presentation/app_routes.dart';
import 'package:grimoire_example/src/features/collections/data/collection_repository.dart';
import 'package:grimoire_example/src/features/collections/presentation/controllers/collections_controller.dart';
import 'package:grimoire_example/src/presentation/controllers/overlays_controller.dart';
import 'package:grimoire_example/src/shared/overlays/overlay_blocks.dart';
import 'package:grimoire_example/src/shared/overlays/overlay_parts.dart';
import 'package:grimoire_example/src/shared/theme/app_theme.dart';
import 'package:grimoire_example/src/shared/widgets/app_icons.dart';
import 'package:grimoire_example/src/shared/widgets/app_widgets.dart';

/// The collections sheet mounted by the shell's sheet host.
class CollectionsSheet extends ConsumerStatefulWidget {
  const CollectionsSheet({super.key});

  @override
  ConsumerState<CollectionsSheet> createState() => _CollectionsSheetState();
}

class _CollectionsSheetState extends ConsumerState<CollectionsSheet> {
  final TextEditingController _nameController = TextEditingController();

  /// The create-form validation error; empty when clean.
  String _error = '';

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// With an acting book the row adds the book to the collection;
  /// without one it filters the home shelf (no toast: the shelf now
  /// really filters).
  void _chooseCollection(final BookCollection collection) {
    final overlays = ref.read(overlaysControllerProvider.notifier);
    final collections = ref.read(collectionsControllerProvider.notifier);
    final bookId = ref.read(overlaysControllerProvider).sheetBookId;
    if (bookId != null) {
      collections.addBook(collection.name, bookId);
      overlays.closeSheet();
      overlays.showToast('Livro adicionado à coleção ${collection.name}.');
      return;
    }
    collections.select(collection.name);
    overlays.closeSheet();
    context.go(AppRoutes.home);
  }

  void _createCollection() {
    final name = _nameController.text;
    final error = ref.read(collectionsControllerProvider.notifier).create(name);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final overlays = ref.read(overlaysControllerProvider.notifier);
    setState(() {
      _error = '';
      _nameController.clear();
    });
    overlays.closeSheet();
    overlays.showToast('Coleção “${name.trim()}” criada.');
  }

  @override
  Widget build(final BuildContext context) {
    final palette = AppScope.of(context);
    final collections = ref.watch(collectionsControllerProvider);

    return SheetFrame(
      title: 'Coleções',
      subtitle: 'Organize seus livros sem sair da biblioteca.',
      onClose: ref.read(overlaysControllerProvider.notifier).closeSheet,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SheetList(
            children: <Widget>[
              for (final collection in collections.all)
                SheetListRow(
                  title: collection.name,
                  subtitle: '${collection.count} livros',
                  onTap: () => _chooseCollection(collection),
                  trailing: AppIcon(
                    collection.name == 'Todos os livros' ? AppIcons.check : AppIcons.chevronRight,
                    size: 18,
                    color: palette.muted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 17),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 17),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: palette.lineSoft)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Nova coleção',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: palette.muted),
                ),
                const SizedBox(height: 7),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Container(
                        height: 42,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: palette.surface2,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: palette.line),
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TextField(
                            controller: _nameController,
                            style: TextStyle(fontSize: 15, color: palette.ink),
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              hintText: 'Ex.: Leituras de verão',
                              hintStyle: TextStyle(fontSize: 15, color: palette.subtle),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AppButton.blue('Criar', _createCollection),
                  ],
                ),
                if (_error.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 13),
                  OverlayAlert(_error),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
