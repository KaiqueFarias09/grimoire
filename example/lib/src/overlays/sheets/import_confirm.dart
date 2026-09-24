part of '../sheets.dart';

class _ImportConfirm extends StatelessWidget {
  const _ImportConfirm({required this.host});

  final DemoHost host;

  @override
  Widget build(final BuildContext context) {
    final state = host.state;
    final imported = host.state.bookById(switch (state.importType) {
      'pdf' => 'pdf',
      'comic' => 'comic',
      'office' => 'office',
      _ => 'alice',
    })!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _ImportPreview(
          book: imported,
          description:
              '${imported.author} · ${imported.formatLabel}\nPronto para entrar na sua biblioteca.',
        ),
        OverlayFooter(
          alignment: MainAxisAlignment.end,
          children: <Widget>[
            AppButton.outline('Voltar', () => host.dispatch('reset-import')),
            AppButton.dark(
              'Adicionar à biblioteca',
              () => host.dispatch('add-imported'),
              icon: AppIcons.library,
            ),
          ],
        ),
      ],
    );
  }
}
