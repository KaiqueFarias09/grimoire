/// Bottom sheets: global library search, the add-book import flow,
/// in-book search, chapter summary and collections, mirroring the
/// prototype's sheet host.
library;

import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../demo_data.dart';
import '../ub_icon.dart';
import '../pages/reader_screen.dart' show ReaderHooks;
import 'package:unseal/unseal.dart' show ComicBook, NavPoint, PdfBook;
import '../ub_theme.dart';
import '../ub_widgets.dart';
import 'shared.dart';

part 'sheets/sheet_frame.dart';
part 'sheets/sheet_close_button.dart';
part 'sheets/sheet_search_box.dart';
part 'sheets/sheet_list.dart';
part 'sheets/sheet_list_row.dart';
part 'sheets/global_search_sheet.dart';
part 'sheets/import_sheet.dart';
part 'sheets/import_picker.dart';
part 'sheets/import_option.dart';
part 'sheets/import_preview.dart';
part 'sheets/import_confirm.dart';
part 'sheets/pdf_password_step.dart';
part 'sheets/reader_search_sheet.dart';
part 'sheets/reader_settings_sheet.dart';
part 'sheets/setting_row.dart';
part 'sheets/setting_option.dart';
part 'sheets/host_note.dart';
part 'sheets/summary_sheet.dart';
part 'sheets/collections_sheet.dart';
part 'sheets/sheet_empty.dart';

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

    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: Semantics(
            button: true,
            label: 'Fechar painel',
            onTap: widget.onDismiss,
            child: GestureDetector(
              excludeFromSemantics: true,
              onTap: widget.onDismiss,
              child: FadeTransition(
                opacity: _curve,
                child: ColoredBox(color: palette.sheetBarrier),
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: SlideTransition(
              position: _slide,
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
                    UbSheet.addBook => _ImportSheet(host: widget.host),
                    UbSheet.readerSearch => _ReaderSearchSheet(host: widget.host),
                    UbSheet.readerSettings => _ReaderSettingsSheet(host: widget.host),
                    UbSheet.summary => _SummarySheet(host: widget.host),
                    UbSheet.collections => _CollectionsSheet(host: widget.host),
                    UbSheet.none => const SizedBox.shrink(),
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
