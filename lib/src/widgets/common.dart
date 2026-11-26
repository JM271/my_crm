import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import '../theme.dart';

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    // A Material (not a decorated Container) so ink splashes of rows inside
    // the panel stay visible.
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(17),
        side: const BorderSide(color: line),
      ),
      child: Container(width: double.infinity, padding: padding, child: child),
    );
  }
}

class PanelHeading extends StatelessWidget {
  const PanelHeading({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(color: muted, fontSize: 11),
              ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Big page title with subtitle and an optional action on the right.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.action,
  });

  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: const TextStyle(color: muted, fontSize: 13),
              ),
            ],
          ),
        ),
        if (action != null) ...[const SizedBox(width: 12), action!],
      ],
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.add_rounded,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 19),
      label: Text(label),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
    );
  }
}

class ContactAvatar extends StatelessWidget {
  const ContactAvatar({super.key, required this.name, this.radius = 18});

  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final palette =
        avatarPalettes[name.codeUnits.fold(0, (a, b) => a + b) %
            avatarPalettes.length];
    return CircleAvatar(
      radius: radius,
      backgroundColor: palette.$1,
      child: Text(
        initialsOf(name),
        style: TextStyle(
          color: palette.$2,
          fontSize: radius * 0.6,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class Tag extends StatelessWidget {
  const Tag({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

(Color, Color) statusColors(ContactStatus status) => switch (status) {
  ContactStatus.klant => (const Color(0xFFE8F1EB), const Color(0xFF397452)),
  ContactStatus.lead => (const Color(0xFFEEF0FA), const Color(0xFF5E6FA8)),
  ContactStatus.partner => (const Color(0xFFF3EDF5), const Color(0xFF8A5E99)),
  ContactStatus.depotVente => (
    const Color(0xFFF9EFE4),
    const Color(0xFFAE733B),
  ),
};

class StatusTag extends StatelessWidget {
  const StatusTag({super.key, required this.status});

  final ContactStatus status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = statusColors(status);
    return Tag(label: status.label, background: bg, foreground: fg);
  }
}

Color stageColor(DealStage stage) => switch (stage) {
  DealStage.nieuw => const Color(0xFF9EBD9C),
  DealStage.inGesprek => const Color(0xFF5D9274),
  DealStage.voorstel => const Color(0xFF3B7058),
  DealStage.gewonnen => forestDark,
  DealStage.verloren => const Color(0xFFC9B5AE),
};

class StageTag extends StatelessWidget {
  const StageTag({super.key, required this.stage});

  final DealStage stage;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (stage) {
      DealStage.gewonnen => (sage, forest),
      DealStage.verloren => (const Color(0xFFF6ECEA), danger),
      _ => (canvas, ink),
    };
    return Tag(label: stage.label, background: bg, foreground: fg);
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: 30, color: muted),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: muted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class AppFormField extends StatelessWidget {
  const AppFormField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.validator,
    this.keyboardType,
    this.maxLines = 1,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final int maxLines;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      maxLines: maxLines,
      autofocus: autofocus,
      decoration: inputDecoration(label, hint),
    );
  }
}

InputDecoration inputDecoration(String label, [String? hint]) =>
    InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: canvas,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: const BorderSide(color: forest),
      ),
    );

class StatData {
  const StatData({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.background,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Color background;
}

class StatsGrid extends StatelessWidget {
  const StatsGrid({super.key, required this.stats});

  final List<StatData> stats;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 14.0;
        final width = constraints.maxWidth;
        final columns = width < 760
            ? 2
            : (stats.length == 5 && width >= 900 ? 5 : 4);
        final cardWidth = (width - spacing * (columns - 1)) / columns;
        // A card left alone on the last row takes the full width.
        final lonelyLast = stats.length % columns == 1;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (var i = 0; i < stats.length; i++)
              SizedBox(
                width: lonelyLast && i == stats.length - 1 ? width : cardWidth,
                child: StatCard(data: stats[i]),
              ),
          ],
        );
      },
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.data});

  final StatData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 132),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  data.title,
                  style: const TextStyle(
                    color: muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: data.background,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(data.icon, color: data.color, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              data.value,
              style: const TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
                color: ink,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            data.subtitle,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: muted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

Future<bool> confirmDelete(
  BuildContext context, {
  required String title,
  required String message,
  String actionLabel = 'Delete',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: danger),
          onPressed: () => Navigator.pop(context, true),
          child: Text(actionLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
