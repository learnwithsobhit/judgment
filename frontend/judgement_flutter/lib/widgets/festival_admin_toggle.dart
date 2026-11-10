import 'package:flutter/material.dart';

import '../auth/account_session.dart';
import '../theme/festival_catalog.dart';
import '../theme/festival_controller.dart';
import '../theme/judgement_palette.dart';

/// Admin-only on/off for the current festival. Lives in the top chrome so it
/// never covers cards. Off sends everyone back to Classic.
class FestivalAdminToggle extends StatelessWidget {
  const FestivalAdminToggle({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        FestivalController.instance,
        AccountSession.instance,
      ]),
      builder: (context, _) {
        final festive = FestivalController.instance;
        if (!AccountSession.instance.isAdmin) {
          return const SizedBox.shrink();
        }
        if (festive.theme.motif == FestivalMotif.none) {
          return const SizedBox.shrink();
        }
        final label = festive.theme.label;
        final switcher = Switch(
          value: true,
          onChanged: festive.pushing
              ? null
              : (on) {
                  if (!on) festive.pushFestival(FestivalTheme.off.id);
                },
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        );
        if (compact) {
          return Tooltip(
            message: '$label is on for everyone. Turn off for Classic.',
            child: Padding(
              padding: const EdgeInsets.only(left: 6, right: 4),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: context.palette.gold.withValues(alpha: 0.5),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(left: 8, right: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: context.palette.title,
                        ),
                      ),
                      SizedBox(
                        height: 28,
                        child: FittedBox(child: switcher),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '$label is on for everyone',
                      style: TextStyle(
                        color: context.palette.title,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  switcher,
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
