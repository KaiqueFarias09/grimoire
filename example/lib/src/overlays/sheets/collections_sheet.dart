part of '../sheets.dart';

class _CollectionsSheet extends StatefulWidget {
  const _CollectionsSheet({required this.host});

  final DemoHost host;

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
    final palette = AppScope.of(context);
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
                            onChanged: (final value) => widget.host.state.newCollectionName = value,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AppButton.blue('Criar', () => widget.host.dispatch('create-collection')),
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
                        const AppIcon(AppIcons.alert, size: 18, color: Color(0xFFB42318)),
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
