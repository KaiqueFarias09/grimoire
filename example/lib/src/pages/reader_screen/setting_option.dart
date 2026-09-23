part of '../reader_screen.dart';

class _SettingOption extends StatelessWidget {
  const _SettingOption({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(final BuildContext context) {
    final palette = UbScope.of(context);
    return Semantics(
      button: true,
      selected: active,
      label: label,
      onTap: onTap,
      child: GestureDetector(
        excludeFromSemantics: true,
        onTap: onTap,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: palette.bg,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: active ? palette.ink : palette.line),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? palette.ink : palette.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
