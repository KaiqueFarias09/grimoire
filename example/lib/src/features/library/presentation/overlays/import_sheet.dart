/// The add-book sheet: the sample picker, the device import flow and
/// the password-protected PDF step. The multi-step flow state (picked
/// type, step, error, typed password) is local to the sheet.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:grimoire_example/src/presentation/app_routes.dart';
import 'package:grimoire_example/src/features/library/data/demo_shelf.dart';
import 'package:grimoire_example/src/features/library/presentation/controllers/shelf_controller.dart';
import 'package:grimoire_example/src/presentation/controllers/overlays_controller.dart';
import 'package:grimoire_example/src/shared/overlays/overlay_blocks.dart';
import 'package:grimoire_example/src/shared/overlays/overlay_parts.dart';
import 'package:grimoire_example/src/shared/theme/app_theme.dart';
import 'package:grimoire_example/src/shared/widgets/app_icons.dart';
import 'package:grimoire_example/src/shared/widgets/app_widgets.dart';

/// The add-book sheet mounted by the shell's sheet host.
class ImportSheet extends ConsumerStatefulWidget {
  const ImportSheet({super.key});

  @override
  ConsumerState<ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends ConsumerState<ImportSheet> {
  /// The picked sample id (`alice`, `pdf`, `comic`, `office`) or an
  /// unsupported format id; empty on the picker step.
  String _type = '';

  /// 1: picker, 2: PDF password, 3: confirm.
  int _step = 1;

  /// The import/unlock error surfaced by the alert banner; empty when
  /// the flow is clean.
  String _error = '';

  final TextEditingController _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  OverlaysController get _overlays => ref.read(overlaysControllerProvider.notifier);

  void _reset() {
    setState(() {
      _type = '';
      _step = 1;
      _error = '';
      _password.clear();
    });
  }

  /// Runs the real device import: a cancelled picker comes back as an
  /// empty failure and is treated silently; a parse failure shows the
  /// alert; a success lands the book on the shelf and jumps home.
  Future<void> _importFromDevice() async {
    final outcome = await ref.read(shelfControllerProvider.notifier).importFromDevice();
    if (!mounted) {
      return;
    }
    switch (outcome) {
      case ImportSuccess(:final book):
        _reset();
        _overlays.dismissAll();
        _overlays.showToast('“${book.title}” importado.');
        context.go(AppRoutes.home);
      case ImportFailure(:final message):
        if (message.isNotEmpty) {
          setState(() => _error = message);
        }
    }
  }

  /// Validates the typed password through the shelf controller; a
  /// success moves to the confirm step with the unlocked preview.
  Future<void> _unlockPdf() async {
    final outcome = await ref.read(shelfControllerProvider.notifier).unlockPdf(_password.text);
    if (!mounted) {
      return;
    }
    switch (outcome) {
      case ImportSuccess():
        setState(() {
          _error = '';
          _step = 3;
        });
      case ImportFailure(:final message):
        if (message.isNotEmpty) {
          setState(() => _error = message);
        }
    }
  }

  /// The sample confirm step: samples are already on the shelf, so
  /// this only closes the overlay and announces the addition.
  void _addSampleToLibrary() {
    _overlays.dismissAll();
    _overlays.showToast('Livro adicionado à sua biblioteca.');
    context.go(AppRoutes.home);
  }

  @override
  Widget build(final BuildContext context) {
    final shelf = ref.watch(shelfControllerProvider);
    final hasType = _type.isNotEmpty;
    final title = hasType ? 'Adicionar livro' : 'Adicionar um livro';
    final intro = hasType
        ? 'Revise o arquivo antes de colocá-lo na sua biblioteca.'
        : 'Escolha uma amostra ou selecione um arquivo do seu dispositivo.';

    final Widget body;
    if (!hasType) {
      body = _ImportPicker(
        onSelect: (final id) => setState(() {
          _type = id;
          _error = '';
          _step = id == 'pdf' ? 2 : 3;
        }),
        onChooseDevice: _importFromDevice,
        onOpenFormatHelp: () => _overlays.openModal(ModalKind.formatHelp),
      );
    } else if (_type == 'kfx') {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const OverlayAlert(
            'Este arquivo não pode ser aberto aqui. Escolha um EPUB, PDF, documento ou quadrinho compatível.',
          ),
          OverlayFooter(
            alignment: MainAxisAlignment.end,
            children: <Widget>[AppButton.outline('Escolher outro arquivo', _reset)],
          ),
        ],
      );
    } else if (_type == 'pdf' && _step == 2) {
      body = _PdfPasswordStep(
        book: shelf.bookById('pdf'),
        error: _error,
        password: _password,
        onBack: _reset,
        onUnlock: _unlockPdf,
      );
    } else {
      final imported = shelf.bookById(switch (_type) {
        'pdf' => 'pdf',
        'comic' => 'comic',
        'office' => 'office',
        _ => 'alice',
      });
      body = imported == null
          ? const SizedBox.shrink()
          : _ImportConfirm(book: imported, onBack: _reset, onConfirm: _addSampleToLibrary);
    }

    return SheetFrame(
      title: title,
      subtitle: intro,
      onClose: _overlays.closeSheet,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[body, if (!hasType) const FormatSection()],
      ),
    );
  }
}

/// The picker step: bundled samples plus the device import entry.
class _ImportPicker extends StatelessWidget {
  const _ImportPicker({
    required this.onSelect,
    required this.onChooseDevice,
    required this.onOpenFormatHelp,
  });

  final void Function(String id) onSelect;
  final VoidCallback onChooseDevice;
  final VoidCallback onOpenFormatHelp;

  @override
  Widget build(final BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 720;
    final options = <(String, String, String, String)>[
      ('alice', AppIcons.bookOpen, 'Alice’s Adventures in Wonderland', 'EPUB · amostra incluída'),
      ('pdf', AppIcons.fileText, 'O pequeno atlas das ideias', 'PDF · senha necessária'),
      ('comic', AppIcons.comic, 'A cidade depois da chuva', 'CBZ · páginas'),
      ('office', AppIcons.fileEdit, 'Cartas para uma casa nova', 'DOCX · documento'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        isMobile
            ? Column(
                children: <Widget>[
                  for (final (id, icon, title, meta) in options)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ImportOption(
                        icon: icon,
                        title: title,
                        meta: meta,
                        onTap: () => onSelect(id),
                      ),
                    ),
                ],
              )
            : Row(
                children: <Widget>[
                  for (final (id, icon, title, meta) in options)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: id == 'alice' ? 0 : 5,
                          right: id == 'office' ? 0 : 5,
                        ),
                        child: _ImportOption(
                          icon: icon,
                          title: title,
                          meta: meta,
                          onTap: () => onSelect(id),
                        ),
                      ),
                    ),
                ],
              ),
        OverlaySection(
          child: OverlayFooter(
            alignment: MainAxisAlignment.start,
            children: <Widget>[
              AppButton.outline('Escolher arquivo', onChooseDevice, icon: AppIcons.upload),
              AppButton.text('Ver formatos aceitos', onOpenFormatHelp),
            ],
          ),
        ),
      ],
    );
  }
}

/// One selectable import source card with its icon, title and meta
/// line.
class _ImportOption extends StatelessWidget {
  const _ImportOption({
    required this.icon,
    required this.title,
    required this.meta,
    required this.onTap,
  });

  final String icon;
  final String title;
  final String meta;
  final VoidCallback onTap;

  @override
  Widget build(final BuildContext context) {
    final palette = AppScope.of(context);
    return AppHover(
      builder: (final context, final hovered) {
        return Semantics(
          button: true,
          label: '$title, $meta',
          onTap: onTap,
          child: GestureDetector(
            excludeFromSemantics: true,
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: hovered ? palette.surface2 : palette.bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: hovered ? palette.ink : palette.lineSoft),
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: palette.surface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(child: AppIcon(icon, size: 18, color: palette.ink)),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(title, style: TextStyle(fontSize: 13, color: palette.ink)),
                        const SizedBox(height: 3),
                        Text(meta, style: TextStyle(fontSize: 11, color: palette.muted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The confirm step: the book preview plus the back/add actions.
class _ImportConfirm extends StatelessWidget {
  const _ImportConfirm({required this.book, required this.onBack, required this.onConfirm});

  final LoadedBook book;
  final VoidCallback onBack;
  final VoidCallback onConfirm;

  @override
  Widget build(final BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _ImportPreview(
          book: book,
          description:
              '${book.author} · ${book.formatLabel}\nPronto para entrar na sua biblioteca.',
        ),
        OverlayFooter(
          alignment: MainAxisAlignment.end,
          children: <Widget>[
            AppButton.outline('Voltar', onBack),
            AppButton.dark('Adicionar à biblioteca', onConfirm, icon: AppIcons.library),
          ],
        ),
      ],
    );
  }
}

/// The cover, title and description block previews show.
class _ImportPreview extends StatelessWidget {
  const _ImportPreview({required this.book, required this.description});

  final LoadedBook book;
  final String description;

  @override
  Widget build(final BuildContext context) {
    final palette = AppScope.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: <Widget>[
          AppCover(entry: book, width: 92, minHeight: 132),
          const SizedBox(width: 17),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(book.title, style: TextStyle(fontSize: 16, color: palette.ink)),
                const SizedBox(height: 5),
                Text(
                  description,
                  style: TextStyle(fontSize: 12, height: 1.45, color: palette.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The password step for the protected PDF fixture.
class _PdfPasswordStep extends StatelessWidget {
  const _PdfPasswordStep({
    required this.book,
    required this.error,
    required this.password,
    required this.onBack,
    required this.onUnlock,
  });

  /// Null while the fixture is still locked (it enters the shelf only
  /// after the password unlocks it).
  final LoadedBook? book;

  /// The unlock error text; empty when clean.
  final String error;
  final TextEditingController password;
  final VoidCallback onBack;
  final VoidCallback onUnlock;

  @override
  Widget build(final BuildContext context) {
    final palette = AppScope.of(context);
    final book = this.book;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (book != null)
          _ImportPreview(
            book: book,
            description: 'PDF protegido. Digite a senha para abrir este livro.',
          )
        else ...<Widget>[
          Text('PDF protegido', style: TextStyle(fontSize: 16, color: palette.ink)),
          const SizedBox(height: 7),
          Text(
            'Digite a senha para abrir este livro.',
            style: TextStyle(fontSize: 12, height: 1.45, color: palette.muted),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Senha do arquivo',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: palette.muted),
        ),
        const SizedBox(height: 7),
        TextField(
          controller: password,
          obscureText: true,
          style: TextStyle(fontSize: 15, color: palette.ink),
          decoration: InputDecoration(
            hintText: 'Digite a senha',
            hintStyle: TextStyle(fontSize: 15, color: palette.subtle),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: palette.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: palette.line),
            ),
            filled: true,
            fillColor: palette.surface2,
          ),
        ),
        if (error.isNotEmpty) ...<Widget>[const SizedBox(height: 13), OverlayAlert(error)],
        OverlayFooter(
          alignment: MainAxisAlignment.end,
          children: <Widget>[
            AppButton.outline('Voltar', onBack),
            AppButton.blue('Abrir livro', onUnlock),
          ],
        ),
        const SizedBox(height: 13),
        Text(
          'Demo: a senha deste arquivo é grimoire.',
          style: TextStyle(fontSize: 11, color: palette.subtle),
        ),
      ],
    );
  }
}
