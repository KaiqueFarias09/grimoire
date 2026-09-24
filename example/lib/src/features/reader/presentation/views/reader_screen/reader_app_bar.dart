/// Pinned reader app bar: back, book title, author and chapter, plus
/// the bookmark and settings actions. Slides away with the rest of
/// the chrome.
library;

import 'package:flutter/material.dart';

import 'package:grimoire_example/src/shared/theme/app_theme.dart';
import 'package:grimoire_example/src/shared/widgets/app_icons.dart';
import 'package:grimoire_example/src/shared/widgets/app_widgets.dart';

/// The reader's top chrome. A pure component: it takes plain data and
/// callbacks and knows nothing about providers or navigation. It
/// returns a [Positioned], so it must sit directly inside the reader
/// screen's [Stack].
class ReaderAppBar extends StatelessWidget {
  const ReaderAppBar({
    required this.title,
    required this.subtitle,
    required this.visible,
    required this.bookmarked,
    required this.settingsActive,
    required this.onBack,
    required this.onToggleBookmark,
    required this.onOpenSettings,
    super.key,
  });

  final String title;
  final String subtitle;
  final bool visible;
  final bool bookmarked;
  final bool settingsActive;
  final VoidCallback onBack;
  final VoidCallback onToggleBookmark;
  final VoidCallback onOpenSettings;

  @override
  Widget build(final BuildContext context) {
    final palette = AppScope.of(context);

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, -1),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        child: IgnorePointer(
          ignoring: !visible,
          child: Container(
            decoration: BoxDecoration(
              color: palette.bg,
              border: Border(bottom: BorderSide(color: palette.lineSoft)),
            ),
            padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
            child: SizedBox(
              height: 56,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: <Widget>[
                    AppIconButton(icon: AppIcons.arrowLeft, tooltip: 'Voltar', onPressed: onBack),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14, color: palette.ink),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: palette.muted),
                          ),
                        ],
                      ),
                    ),
                    AppIconButton(
                      icon: AppIcons.bookmark,
                      tooltip: 'Marcar posição',
                      active: bookmarked,
                      onPressed: onToggleBookmark,
                    ),
                    const SizedBox(width: 4),
                    AppIconButton(
                      icon: AppIcons.type,
                      tooltip: 'Temas e ajustes',
                      active: settingsActive,
                      onPressed: onOpenSettings,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
