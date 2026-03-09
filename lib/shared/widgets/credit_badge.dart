import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/widgets/login_bottom_sheet.dart';
import '../../features/billing/providers/credit_provider.dart';

/// AppBar 右上角的點數 + 帳號狀態徽章
///
/// - **已登入**：顯示點數（漸層/灰色）
/// - **訪客**：顯示點數 + 人型 icon，點擊可登入
class CreditBadge extends ConsumerWidget {
  const CreditBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final credits = ref.watch(creditProvider);
    final isGuest = ref.watch(isGuestProvider);
    final isLow = credits <= 0;

    return GestureDetector(
      onTap: isGuest
          ? () => LoginBottomSheet.show(context)
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          gradient: (!isLow && !isGuest) ? AppColors.gradient : null,
          color: (isLow || isGuest) ? const Color(0xFFF2F2F7) : null,
          borderRadius: BorderRadius.circular(20),
          border: isGuest
              ? Border.all(
                  color: AppColors.divider,
                  width: 1,
                )
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 訪客顯示人型 icon（可登入提示）
            if (isGuest)
              Icon(
                Icons.person_outline_rounded,
                size: 13,
                color: AppColors.textSecondary,
              )
            else
              Icon(
                isLow ? Icons.bolt_outlined : Icons.bolt_rounded,
                size: 14,
                color: isLow ? AppColors.textSecondary : Colors.white,
              ),
            const SizedBox(width: 3),
            Text(
              '$credits',
              style: GoogleFonts.notoSansTc(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: (isGuest || isLow)
                    ? AppColors.textSecondary
                    : Colors.white,
              ),
            ),
            if (isGuest) ...[
              const SizedBox(width: 3),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 14,
                color: AppColors.textSecondary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
