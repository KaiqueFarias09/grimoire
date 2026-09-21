/// Bottom sheets: global library search, in-book search, chapter
/// summary and collections, mirroring the prototype's sheet host.
library;

import 'package:flutter/material.dart';

import '../app_shell.dart';
import '../ub_icon.dart';
import '../pages/reader_screen.dart' show ReaderHooks;
import 'package:unseal/unseal.dart' show NavPoint;
import '../ub_theme.dart';
import '../ub_widgets.dart';

class UbSheetHost extends StatefulWidget {
  const UbSheetHost({required this.host, required this.sheet, required this.onDismiss, super.key});

  final UbHost host;
  final UbSheet sheet;
  final VoidCallback onDismiss;

  @override
  State<UbSheetHost> createState() => _UbSheetHostState();
}

/// Mounted for the shell's whole life: the sheet slides up from the
/// bottom edge on open and back down on close, while the barrier fades.
class _UbSheetHostState extends State<UbSheetHost> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    reverseDuration: const Duration(milliseconds: 220),
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 1),
    end: Offset.zero,
  ).animate(_curve);

  /// The sheet shown while animating: the shell clears `sheet` to none
  /// on dismiss, but the content must stay visible until the slide-out
  /// finishes.
  UbSheet _contentSheet = UbSheet.none;

  @override
  void initState() {
    super.initState();
    // Screenshot automation mounts the shell with a sheet already open.
    if (widget.sheet != UbSheet.none) {
      _contentSheet = widget.sheet;
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(final UbSheetHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sheet != UbSheet.none) {
      _contentSheet = widget.sheet;
      if (oldWidget.sheet == UbSheet.none) {
        _controller.forward(from: 0);
      }
    } else if (oldWidget.sheet != UbSheet.none) {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    if (widget.sheet == UbSheet.none && _controller.isDismissed) {
      return const SizedBox.shrink();
    }
    final palette = UbScope.of(context);
    final isMobile = MediaQuery.sizeOf(context).width < 720;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return GestureDetector(
      onTap: widget.onDismiss,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: FadeTransition(
              opacity: _curve,
              child: ColoredBox(color: palette.sheetBarrier),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: SlideTransition(
                position: _slide,
                child: GestureDetector(
                  onTap: () {},
                  child: Container(
                    width: double.infinity,
                    // Fully extended: the whole screen minus any open keyboard.
                    height: MediaQuery.sizeOf(context).height - bottomInset,
                    margin: EdgeInsets.symmetric(horizontal: isMobile ? 0.0 : 18.0),
                    constraints: const BoxConstraints(maxWidth: 680),
                    padding: EdgeInsets.fromLTRB(
                      isMobile ? 16 : 22,
                      // The header must clear the system status bar:
                      // taps inside that band never reach the app.
                      MediaQuery.paddingOf(context).top + 10,
                      isMobile ? 16 : 22,
                      isMobile ? 22 : 24,
                    ),
                    decoration: BoxDecoration(
                      color: palette.bg,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                      boxShadow: <BoxShadow>[
                        const BoxShadow(
                          color: Color(0x24000000),
                          blurRadius: 42,
                          offset: Offset(0, -16),
                        ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      child: switch (_contentSheet) {
                        UbSheet.globalSearch => _GlobalSearchSheet(host: widget.host),
                        UbSheet.readerSearch => _ReaderSearchSheet(host: widget.host),
                        UbSheet.summary => _SummarySheet(host: widget.host),
                        UbSheet.collections => _CollectionsSheet(host: widget.host),
                        UbSheet.none => const SizedBox.shrink(),
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.title,
    required this.subtitle,
    required this.body,
    required this.onClose,
  });

  final String title;
  final String subtitle;
  final Widget body;
  final VoidCallback onClose;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Center(
          child: Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 18),
            decoration: BoxDecoration(color: palette.line, borderRadius: BorderRadius.circular(99)),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 22 * -0.025,
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: palette.muted)),
                ],
              ),
            ),
            const SizedBox(width: 18),
            _SheetCloseButton(onClose: onClose),
          ],
        ),
        const SizedBox(height: 18),
        body,
      ],
    );
  }
}

class _SheetCloseButton extends StatelessWidget {
  const _SheetCloseButton({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return GestureDetector(
      onTap: onClose,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(color: palette.surface, shape: BoxShape.circle),
        child: Center(child: UbIcon(UbIcons.close, size: 18, color: palette.muted)),
      ),
    );
  }
}

class _SheetSearchBox extends StatefulWidget {
  const _SheetSearchBox({
    required this.hint,
    required this.initialValue,
    required this.onSubmitted,
  });

  final String hint;
  final String initialValue;
  final void Function(String value) onSubmitted;

  @override
  State<_SheetSearchBox> createState() => _SheetSearchBoxState();
}

class _SheetSearchBoxState extends State<_SheetSearchBox> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: palette.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.line),
      ),
      child: Row(
        children: <Widget>[
          UbIcon(UbIcons.search, size: 18, color: palette.muted),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _controller,
              style: TextStyle(fontSize: 15, color: palette.ink),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                hintText: widget.hint,
                hintStyle: TextStyle(fontSize: 15, color: palette.subtle),
              ),
              onSubmitted: widget.onSubmitted,
            ),
          ),
          UbIconButton(
            icon: UbIcons.arrowRight,
            onPressed: () => widget.onSubmitted(_controller.text),
          ),
        ],
      ),
    );
  }
}

/// The prototype's `.ub-sheet-list`: rows under a soft top border.
class _SheetList extends StatelessWidget {
  const _SheetList({required this.children});

  final List<Widget> children;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.lineSoft)),
      ),
      child: Column(children: children),
    );
  }
}

class _SheetListRow extends StatelessWidget {
  const _SheetListRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    this.active = false,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool active;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return UbHover(
      builder: (final context, final hovered) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 62),
            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: palette.lineSoft)),
              color: active || hovered ? palette.surface2 : Colors.transparent,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(title, style: TextStyle(fontSize: 13, color: palette.ink)),
                      const SizedBox(height: 4),
                      Text(subtitle, style: TextStyle(fontSize: 11, color: palette.muted)),
                    ],
                  ),
                ),
                if (trailing != null) ...<Widget>[const SizedBox(width: 16), trailing!],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GlobalSearchSheet extends StatelessWidget {
  const _GlobalSearchSheet({required this.host});

  final UbHost host;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    final state = host.state;
    final query = state.searchQuery.trim().toLowerCase();
    final results = query.isNotEmpty
        ? state.books
              .where(
                (final book) => '${book.title} ${book.author} ${book.formatLabel}'
                    .toLowerCase()
                    .contains(query),
              )
              .toList()
        : state.books.take(3).toList();

    final Widget resultMarkup = results.isNotEmpty
        ? _SheetList(
            children: <Widget>[
              for (final book in results)
                _SheetListRow(
                  title: book.title,
                  subtitle: '${book.author} · ${book.formatLabel}',
                  onTap: () => host.dispatch('open-detail', data: book.fixture.id),
                  trailing: UbIcon(UbIcons.chevronRight, size: 18, color: palette.muted),
                ),
            ],
          )
        : const _SheetEmpty('Nenhum livro encontrado. Tente outro título ou autor.');

    return _SheetFrame(
      title: 'Buscar',
      subtitle: 'Encontre um livro na sua biblioteca.',
      onClose: () => host.dispatch('close-sheet'),
      body: Column(
        children: <Widget>[
          _SheetSearchBox(
            hint: 'Título, autor ou formato',
            initialValue: state.searchQuery,
            onSubmitted: (final value) {
              host.state.searchQuery = value;
              host.dispatch('run-sheet-search');
            },
          ),
          const SizedBox(height: 30),
          resultMarkup,
        ],
      ),
    );
  }
}

class _ReaderSearchSheet extends StatelessWidget {
  const _ReaderSearchSheet({required this.host});

  final UbHost host;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    final state = host.state;
    final book = state.bookById(state.selectedBook);

    final Widget results;
    if (state.searchRan) {
      results = Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(color: palette.blueSoft, borderRadius: BorderRadius.circular(9)),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '“${state.searchQuery.isEmpty ? 'livro' : state.searchQuery}”',
                    style: TextStyle(fontSize: 13, color: palette.ink),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '2 resultados · Capítulo V · 38%',
                    style: TextStyle(fontSize: 11, color: palette.muted),
                  ),
                ],
              ),
            ),
            UbLinkButton(
              label: 'Ir para lá',
              chevron: false,
              onPressed: () => host.dispatch('jump-to-result'),
            ),
          ],
        ),
      );
    } else {
      results = const _SheetEmpty(
        'Busque uma palavra ou frase para encontrar uma passagem neste livro.',
      );
    }

    return _SheetFrame(
      title: 'Buscar no livro',
      subtitle: book?.title ?? '',
      onClose: () => host.dispatch('close-sheet'),
      body: Column(
        children: <Widget>[
          _SheetSearchBox(
            hint: 'Buscar uma palavra ou frase',
            initialValue: state.searchQuery,
            onSubmitted: (final value) {
              host.state.searchQuery = value;
              host.dispatch('run-sheet-search');
            },
          ),
          results,
        ],
      ),
    );
  }
}

class _SummarySheet extends StatelessWidget {
  const _SummarySheet({required this.host});

  final UbHost host;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    final toc = ReaderHooks.tocSource?.call() ?? const <NavPoint>[];
    if (toc.isEmpty) {
      return _SheetFrame(
        title: 'Sumário',
        subtitle: 'Escolha onde você quer continuar.',
        onClose: () => host.dispatch('close-sheet'),
        body: _SheetList(
          children: <Widget>[
            _SheetListRow(
              title: 'Capítulo V',
              subtitle: 'Conselhos de uma lagarta',
              active: true,
              onTap: () => host.dispatch('select-chapter'),
              trailing: Text('38%', style: TextStyle(fontSize: 13, color: palette.muted)),
            ),
            _SheetListRow(
              title: 'Capítulo VI',
              subtitle: 'Porco e pimenta',
              onTap: () => host.dispatch('select-chapter'),
              trailing: Text('46%', style: TextStyle(fontSize: 13, color: palette.muted)),
            ),
            _SheetListRow(
              title: 'Capítulo VII',
              subtitle: 'Uma festa',
              onTap: () => host.dispatch('select-chapter'),
              trailing: Text('55%', style: TextStyle(fontSize: 13, color: palette.muted)),
            ),
            _SheetListRow(
              title: 'Capítulo VIII',
              subtitle: 'O campo de croquet',
              onTap: () => host.dispatch('select-chapter'),
              trailing: Text('71%', style: TextStyle(fontSize: 13, color: palette.muted)),
            ),
          ],
        ),
      );
    }

    return _SheetFrame(
      title: 'Sumário',
      subtitle: 'Escolha onde você quer continuar.',
      onClose: () => host.dispatch('close-sheet'),
      body: _SheetList(
        children: <Widget>[
          for (final (index, point) in toc.indexed)
            _SheetListRow(
              title: point.label,
              subtitle:
                  '${((index + 1) / toc.length * 100).round()}% · ${point.content.split('/').last}',
              active: index == 0,
              onTap: () => host.dispatch('select-chapter', data: '$index'),
              trailing: Text(
                '${((index + 1) / toc.length * 100).round()}%',
                style: TextStyle(fontSize: 13, color: palette.muted),
              ),
            ),
        ],
      ),
    );
  }
}

class _CollectionsSheet extends StatefulWidget {
  const _CollectionsSheet({required this.host});

  final UbHost host;

  @override
  State<_CollectionsSheet> createState() => _CollectionsSheetState();
}

class _CollectionsSheetState extends State<_CollectionsSheet> {
  final TextEditingController _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    final state = widget.host.state;

    return _SheetFrame(
      title: 'Coleções',
      subtitle: 'Organize seus livros sem sair da biblioteca.',
      onClose: () => widget.host.dispatch('close-sheet'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SheetList(
            children: <Widget>[
              for (final collection in state.collections)
                _SheetListRow(
                  title: collection.name,
                  subtitle: '${collection.count} livros',
                  onTap: () => widget.host.dispatch('choose-collection', data: collection.name),
                  trailing: UbIcon(
                    collection.name == 'Todos os livros' ? UbIcons.check : UbIcons.chevronRight,
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
                            onChanged: (final value) => widget.host.state.newCollectionName = value,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    UbButton.blue('Criar', () => widget.host.dispatch('create-collection')),
                  ],
                ),
                if (state.collectionError.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 13),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1F0),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const UbIcon(UbIcons.alert, size: 18, color: Color(0xFFB42318)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            state.collectionError,
                            style: const TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: Color(0xFFB42318),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetEmpty extends StatelessWidget {
  const _SheetEmpty(this.message);

  final String message;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 15),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: palette.surface, borderRadius: BorderRadius.circular(9)),
      child: Text(message, style: TextStyle(fontSize: 12, height: 1.45, color: palette.muted)),
    );
  }
}
