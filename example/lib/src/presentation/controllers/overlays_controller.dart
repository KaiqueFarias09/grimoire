/// App-level overlay state: which sheet or modal is mounted, the
/// transient toast and the payloads overlays need. The overlay hosts
/// in the shell watch this controller; feature sheets read their own
/// feature controllers for data.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The bottom sheets the shell can mount.
enum SheetKind { globalSearch, importBook, readerSearch, readerSettings, summary, collections }

/// The centered modals the shell can mount.
enum ModalKind { formatHelp, note }

class OverlaysState {
  const OverlaysState({this.sheet, this.modal, this.noteQuote = '', this.toast = ''});

  final SheetKind? sheet;
  final ModalKind? modal;

  /// The selected passage shown by the note modal; set when the modal
  /// opens, cleared when it closes.
  final String noteQuote;

  final String toast;

  bool get hasOverlay => sheet != null || modal != null;

  OverlaysState copyWith({
    SheetKind? sheet,
    ModalKind? modal,
    String? noteQuote,
    String? toast,
    bool clearSheet = false,
    bool clearModal = false,
  }) {
    return OverlaysState(
      sheet: clearSheet ? null : (sheet ?? this.sheet),
      modal: clearModal ? null : (modal ?? this.modal),
      noteQuote: noteQuote ?? this.noteQuote,
      toast: toast ?? this.toast,
    );
  }
}

class OverlaysController extends Notifier<OverlaysState> {
  Timer? _toastTimer;

  @override
  OverlaysState build() {
    ref.onDispose(() => _toastTimer?.cancel());

    return const OverlaysState();
  }

  void openSheet(final SheetKind kind) => state = state.copyWith(sheet: kind, clearModal: true);

  /// Opens the note editor over the passage the reader selection
  /// returned; an empty quote means there was no selection.
  void openNoteModal(final String quote) =>
      state = state.copyWith(modal: ModalKind.note, noteQuote: quote, clearSheet: true);

  void openModal(final ModalKind kind) => state = state.copyWith(modal: kind, clearSheet: true);

  void closeSheet() => state = state.copyWith(clearSheet: true);

  void closeModal() => state = state.copyWith(clearModal: true);

  /// The Escape handler: dismisses whichever overlay is on top.
  void closeTop() {
    if (state.modal != null) {
      closeModal();
    } else if (state.sheet != null) {
      closeSheet();
    }
  }

  /// Clears every overlay, used when navigation swaps screens.
  void dismissAll() => state = state.copyWith(clearSheet: true, clearModal: true);

  void showToast(final String message) {
    _toastTimer?.cancel();
    state = state.copyWith(toast: message);
    _toastTimer = Timer(const Duration(milliseconds: 2300), () {
      if (state.toast == message) {
        state = state.copyWith(toast: '');
      }
    });
  }
}

final overlaysControllerProvider = NotifierProvider<OverlaysController, OverlaysState>(
  OverlaysController.new,
);

/// Pre-opens an overlay from the `UB_OVERLAY` screenshot flag; unknown
/// values mount nothing.
SheetKind? sheetKindFromFlag(final String flag) => switch (flag) {
  'add' => SheetKind.importBook,
  'search' => SheetKind.globalSearch,
  'collections' => SheetKind.collections,
  'summary' => SheetKind.summary,
  'settings' => SheetKind.readerSettings,
  _ => null,
};

@visibleForTesting
ModalKind? modalKindFromFlag(final String flag) => flag == 'note' ? ModalKind.note : null;
