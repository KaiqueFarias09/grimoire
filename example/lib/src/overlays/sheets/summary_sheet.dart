part of '../sheets.dart';

class _SummarySheet extends StatelessWidget {
  const _SummarySheet({required this.host});

  final DemoHost host;

  @override
  Widget build(final BuildContext context) {
    final palette = AppScope.of(context);
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
