import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'api/api_client.dart';
import 'theme.dart';

void showVizeError(BuildContext context, Object error) {
  final text = error is ApiException ? '${error.code}: ${error.title}' : '$error';
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

void showVizeMessage(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

void popOrGo(BuildContext context, String location) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(location);
  }
}

class VizeLogo extends StatelessWidget {
  const VizeLogo({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Text(
      'Vize',
      style: TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w700,
        color: VizeColors.accent,
        letterSpacing: -0.4,
        height: 1,
      ),
    );
  }
}

class VizeHeader extends StatelessWidget {
  const VizeHeader({
    super.key,
    this.title,
    this.showLogo = false,
    this.trailing,
  });

  final String? title;
  final bool showLogo;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final canPop = context.canPop();
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (canPop && !showLogo)
                IconButton(
                  tooltip: 'Назад',
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.chevron_left, size: 28, color: VizeColors.accentMuted),
                )
              else if (showLogo)
                const Padding(
                  padding: EdgeInsets.only(left: 12, top: 8, bottom: 8),
                  child: VizeLogo(),
                )
              else
                const SizedBox(width: 12),
              const Spacer(),
              ?trailing,
            ],
          ),
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Text(title!, style: Theme.of(context).textTheme.headlineLarge),
            ),
        ],
      ),
    );
  }
}

class VizeScaffold extends StatelessWidget {
  const VizeScaffold({
    super.key,
    required this.body,
    this.header,
    this.tabIndex,
  });

  final Widget body;
  final Widget? header;
  final int? tabIndex;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: VizeTheme.overlay,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ?header,
              Expanded(child: body),
              if (tabIndex != null) VizeTabBar(index: tabIndex!),
            ],
          ),
        ),
      ),
    );
  }
}

class VizeTabBar extends StatelessWidget {
  const VizeTabBar({super.key, required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: _TabItem(
              icon: Icons.home_outlined,
              label: 'Дом',
              selected: index == 0,
              onTap: () => context.go('/home'),
            ),
          ),
          Expanded(
            child: _TabItem(
              icon: Icons.search,
              label: 'Поиск',
              selected: false,
              onTap: () => showVizeMessage(context, 'Поиск появится вместе с каталогом.'),
            ),
          ),
          Expanded(
            child: _TabItem(
              icon: Icons.menu,
              label: 'Меню',
              selected: index == 1,
              onTap: () => context.go('/settings'),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.icon,
    required this.label,
    required this.selected,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? VizeColors.textOnAccent : VizeColors.accentMuted;
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 22, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
        ),
      ],
    );
    if (!selected) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(VizeRadii.pill),
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: child),
      );
    }
    return Center(
      child: Material(
        color: VizeColors.accent,
        borderRadius: BorderRadius.circular(VizeRadii.pill),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(VizeRadii.pill),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: child,
          ),
        ),
      ),
    );
  }
}

class VizeChip extends StatelessWidget {
  const VizeChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? VizeColors.accent : Colors.transparent,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? VizeColors.accent : VizeColors.accentDim),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: selected ? VizeColors.textOnAccent : VizeColors.accentMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class IdentifierTypeField extends StatelessWidget {
  const IdentifierTypeField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        VizeChip(label: 'Email', selected: value == 'email', onTap: () => onChanged('email')),
        const SizedBox(width: 8),
        VizeChip(label: 'Логин', selected: value == 'login', onTap: () => onChanged('login')),
      ],
    );
  }
}

class VizePasswordField extends StatefulWidget {
  const VizePasswordField({
    super.key,
    required this.controller,
    required this.label,
  });

  final TextEditingController controller;
  final String label;

  @override
  State<VizePasswordField> createState() => _VizePasswordFieldState();
}

class _VizePasswordFieldState extends State<VizePasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _obscure,
      decoration: InputDecoration(
        labelText: widget.label,
        suffixIcon: IconButton(
          tooltip: _obscure ? 'Показать пароль' : 'Скрыть пароль',
          onPressed: () => setState(() => _obscure = !_obscure),
          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
        ),
      ),
    );
  }
}

class VizeCodeField extends StatelessWidget {
  const VizeCodeField({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      maxLength: 6,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: const InputDecoration(
        labelText: 'Код из письма',
        counterText: '',
      ),
    );
  }
}

class VizePrimaryButton extends StatelessWidget {
  const VizePrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: VizeColors.textOnAccent),
            )
          : Text(label),
    );
  }
}

class VizeCard extends StatelessWidget {
  const VizeCard({super.key, required this.child, this.onTap, this.padding});

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: padding ?? const EdgeInsets.all(16),
      child: child,
    );
    return Material(
      color: VizeColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VizeRadii.card),
        side: const BorderSide(color: VizeColors.stroke),
      ),
      child: onTap == null
          ? body
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(VizeRadii.card),
              child: body,
            ),
    );
  }
}

class VizeSettingRow extends StatelessWidget {
  const VizeSettingRow({
    super.key,
    required this.icon,
    required this.label,
    this.value,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return VizeCard(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: VizeColors.accentMuted),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: Theme.of(context).textTheme.titleMedium)),
          if (value != null)
            Text(value!, style: const TextStyle(color: VizeColors.accent, fontWeight: FontWeight.w600)),
          ?trailing,
          if (onTap != null && trailing == null)
            const Icon(Icons.chevron_right, color: VizeColors.accentMuted),
        ],
      ),
    );
  }
}
