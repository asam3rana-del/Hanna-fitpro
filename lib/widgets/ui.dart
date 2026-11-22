import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../db/user_repository.dart';
import '../models/models.dart';
import '../services/photo_service.dart';
import '../theme/theme_manager.dart';
import '../utils/fmt.dart';
import '../utils/loc.dart';

AppPalette get pal => ThemeManager.palette;

bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= 900;

/// Saari sub-screens ka saaf (flat) app bar.
PreferredSizeWidget gymAppBar(String title, {List<Widget>? actions, String? subtitle}) => AppBar(
      backgroundColor: pal.bg,
      foregroundColor: pal.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 4,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: TextStyle(color: pal.ink, fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: 0.2)),
          if (subtitle != null && subtitle.isNotEmpty)
            Text(subtitle, style: TextStyle(color: pal.muted, fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
      actions: actions,
    );

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

Future<bool> confirm(BuildContext context, String title, String message,
    {String? yes, bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: pal.card,
      title: Text(title, style: TextStyle(color: pal.ink, fontWeight: FontWeight.w800)),
      content: Text(message, style: TextStyle(color: pal.muted)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(Loc.t('Cancel', 'منسوخ'))),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: pal.red, foregroundColor: Colors.white) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(yes ?? Loc.t('Yes', 'ہاں')),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Gold patli line + premium chhota heading.
class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
        child: Row(children: [
          Container(width: 4, height: 16, decoration: BoxDecoration(color: pal.gold, borderRadius: BorderRadius.circular(4))),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text.toUpperCase(),
                style: TextStyle(color: pal.muted, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}

/// Saaf card (halka border, gol kone).
class PCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;
  const PCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.color, this.borderColor});

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? pal.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor ?? pal.border),
        boxShadow: pal.isDark
            ? null
            : [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: child,
    );
    if (onTap == null) return box;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: BorderRadius.circular(18), onTap: onTap, child: box),
    );
  }
}

/// Black + gold premium header (dashboard / profile).
class HeroHeader extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const HeroHeader({super.key, required this.child, this.padding = const EdgeInsets.fromLTRB(20, 20, 20, 20)});

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [pal.header, pal.header2],
          ),
          border: Border.all(color: pal.gold.withValues(alpha: 0.35)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 8))],
        ),
        child: child,
      );
}

/// Dashboard ka number card.
class StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final Color soft;
  final String? hint;
  final VoidCallback? onTap;
  const StatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.soft,
    this.hint,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => PCard(
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 20),
            ),
            const Spacer(),
            if (onTap != null) Icon(Icons.chevron_right, color: pal.muted, size: 18),
          ]),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(value, style: TextStyle(color: pal.ink, fontSize: 22, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 2),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: pal.muted, fontSize: 12.5)),
          if (hint != null)
            Text(hint!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ]),
      );
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final Color soft;
  final IconData? icon;
  const Pill(this.text, {super.key, required this.color, required this.soft, this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(30)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 4)],
          Text(text, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ]),
      );
}

/// Membership haalat ka rangeen nishan.
class StatePill extends StatelessWidget {
  final MemberSummary s;
  const StatePill(this.s, {super.key});

  static (String, Color, Color) describe(MemberSummary s, int reminderDays) {
    final d = s.daysLeft;
    return switch (s.stateFor(reminderDays)) {
      MemberState.active => (Loc.t('$d days left', '$d دن باقی'), pal.green, pal.greenSoft),
      MemberState.expiring => (
          d == 0 ? Loc.t('Expires today', 'آج ختم') : Loc.t('$d days left', '$d دن باقی'),
          pal.amber,
          pal.amberSoft
        ),
      MemberState.expired => (Loc.t('Expired ${-d}d ago', '${-d} دن پہلے ختم'), pal.red, pal.redSoft),
      MemberState.inactive => (Loc.t('Inactive', 'غیر فعال'), pal.muted, pal.cardAlt),
      MemberState.none => (Loc.t('No plan', 'کوئی پلان نہیں'), pal.blue, pal.blueSoft),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (text, c, soft) = describe(s, GymSettings.reminderDays);
    return Pill(text, color: c, soft: soft);
  }
}

/// Member ki tasveer (lazy) — na ho to gold ring mein initials.
class MemberAvatar extends StatelessWidget {
  final String memberId;
  final String name;
  final bool hasPhoto;
  final double size;
  const MemberAvatar({super.key, required this.memberId, required this.name, required this.hasPhoto, this.size = 46});

  Widget _initials() => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(colors: [pal.gold, pal.goldDark], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: Text(Fmt.initials(name),
            style: TextStyle(color: pal.onGold, fontWeight: FontWeight.w800, fontSize: size * 0.36)),
      );

  @override
  Widget build(BuildContext context) {
    if (!hasPhoto) return _initials();
    return ValueListenableBuilder<int>(
      valueListenable: PhotoService.changes,
      builder: (context, _, __) => FutureBuilder<Uint8List?>(
        future: PhotoService.bytesFor(memberId),
        builder: (context, snap) {
          final b = snap.data;
          if (b == null) return _initials();
          return Container(
            width: size,
            height: size,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: pal.gold, width: 1.5)),
            child: ClipOval(child: Image.memory(b, fit: BoxFit.cover, width: size, height: size, gaplessPlayback: true)),
          );
        },
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle, this.action});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: pal.goldSoft, shape: BoxShape.circle),
              child: Icon(icon, color: pal.gold, size: 34),
            ),
            const SizedBox(height: 14),
            Text(title, textAlign: TextAlign.center, style: TextStyle(color: pal.ink, fontSize: 16, fontWeight: FontWeight.w700)),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!, textAlign: TextAlign.center, style: TextStyle(color: pal.muted)),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ]),
        ),
      );
}

/// Label: value ki ek line (profile / receipts).
class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  const InfoRow(this.label, this.value, {super.key, this.icon});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (icon != null) ...[Icon(icon, size: 18, color: pal.gold), const SizedBox(width: 10)],
          SizedBox(width: 120, child: Text(label, style: TextStyle(color: pal.muted))),
          Expanded(child: Text(value.isEmpty ? '-' : value, style: TextStyle(color: pal.ink, fontWeight: FontWeight.w600))),
        ]),
      );
}

/// Choti chips ki row (filters).
class ChoiceChips<T> extends StatelessWidget {
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  const ChoiceChips({super.key, required this.options, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final o in options)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: GestureDetector(
                onTap: () => onChanged(o.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: o.$1 == value ? pal.gold : pal.card,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: o.$1 == value ? pal.gold : pal.border),
                  ),
                  child: Text(o.$2,
                      style: TextStyle(
                          color: o.$1 == value ? pal.onGold : pal.ink, fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              ),
            ),
        ]),
      );
}

/// Bara gold button (sheets ke neeche).
class GoldButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool busy;
  const GoldButton({super.key, required this.label, this.icon, this.onPressed, this.busy = false});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton.icon(
          onPressed: busy ? null : onPressed,
          icon: busy
              ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: pal.onGold))
              : Icon(icon ?? Icons.check),
          label: Text(label, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
        ),
      );
}

/// Bottom sheet ka dhancha (handle + title + scroll).
Future<T?> showGymSheet<T>(BuildContext context, {required String title, required Widget Function(BuildContext) builder}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: pal.card,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.92, maxWidth: 640),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: pal.border, borderRadius: BorderRadius.circular(4)),
              ),
            ),
            Text(title, style: TextStyle(color: pal.ink, fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            builder(ctx),
          ]),
        ),
      ),
    ),
  );
}

/// Tareekh chunne ka button.
class DateField extends StatelessWidget {
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final DateTime? first;
  final DateTime? last;
  const DateField({super.key, required this.label, required this.value, required this.onChanged, this.first, this.last});

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          final d = await showDatePicker(
            context: context,
            initialDate: value,
            firstDate: first ?? DateTime(2015),
            lastDate: last ?? DateTime(2100),
          );
          if (d != null) onChanged(DateTime.utc(d.year, d.month, d.day));
        },
        child: InputDecorator(
          decoration: ThemeManager.field(label, icon: Icons.event),
          child: Text(Fmt.dateOf(value), style: TextStyle(color: pal.ink, fontWeight: FontWeight.w600)),
        ),
      );
}

/// Payment ke tareeqe.
const List<String> paymentMethods = ['Cash', 'JazzCash', 'Easypaisa', 'Bank Transfer', 'Card'];
