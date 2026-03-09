import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_colors.dart';

/// 登入底部彈窗
///
/// 適用場景：
/// - 訪客點數不足，想用登入換 5 點
/// - 使用者主動要求登入（AppBar 點數徽章點擊）
///
/// 回傳 `true` = 登入成功（可繼續操作）
class LoginBottomSheet extends ConsumerStatefulWidget {
  const LoginBottomSheet({super.key});

  static Future<bool> show(BuildContext context) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const LoginBottomSheet(),
    );
    return result ?? false;
  }

  @override
  ConsumerState<LoginBottomSheet> createState() => _LoginBottomSheetState();
}

class _LoginBottomSheetState extends ConsumerState<LoginBottomSheet> {
  bool _isLoadingGoogle = false;
  bool _isLoadingApple = false;

  Future<void> _loginWithGoogle() async {
    if (_isLoadingGoogle || _isLoadingApple) return;
    setState(() => _isLoadingGoogle = true);

    final result = await AuthService.signInWithGoogle();

    if (!mounted) return;
    setState(() => _isLoadingGoogle = false);

    if (result.isSuccess) {
      Navigator.of(context).pop(true);
    } else if (result.isError) {
      _showError('Google 登入失敗，請再試一次');
    }
  }

  Future<void> _loginWithApple() async {
    if (_isLoadingGoogle || _isLoadingApple) return;
    setState(() => _isLoadingApple = true);

    final result = await AuthService.signInWithApple();

    if (!mounted) return;
    setState(() => _isLoadingApple = false);

    if (result.isSuccess) {
      Navigator.of(context).pop(true);
    } else if (result.isError) {
      _showError('Apple 登入失敗，請再試一次');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.notoSansTc(fontSize: 13)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Drag handle ────────────────────────────────────────────
          const SizedBox(height: 14),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          // ── 圖示 ───────────────────────────────────────────────────
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: AppColors.gradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.person_add_rounded,
              color: Colors.white,
              size: 34,
            ),
          ),
          const SizedBox(height: 16),

          // ── 標題 ───────────────────────────────────────────────────
          ShaderMask(
            shaderCallback: (b) => AppColors.gradient.createShader(b),
            child: Text(
              '登入獲得 5 點',
              style: GoogleFonts.notoSansTc(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '登入帳號可跨裝置同步點數\n並獲得 5 點初始獎勵 🎉',
            style: GoogleFonts.notoSansTc(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),

          // ── Google 登入 ────────────────────────────────────────────
          _SocialLoginButton(
            isLoading: _isLoadingGoogle,
            onTap: _loginWithGoogle,
            icon: _GoogleIcon(),
            label: '使用 Google 帳號登入',
            backgroundColor: Colors.white,
            foregroundColor: AppColors.textPrimary,
            borderColor: AppColors.divider,
          ),

          // ── Apple 登入（僅 iOS 顯示）──────────────────────────────
          if (Platform.isIOS) ...[
            const SizedBox(height: 12),
            _SocialLoginButton(
              isLoading: _isLoadingApple,
              onTap: _loginWithApple,
              icon: const Icon(Icons.apple, size: 24, color: Colors.white),
              label: '使用 Apple ID 登入',
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
            ),
          ],

          const SizedBox(height: 20),

          // ── 繼續訪客 ──────────────────────────────────────────────
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              '繼續以訪客身份使用',
              style: GoogleFonts.notoSansTc(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Social 登入按鈕 ────────────────────────────────────────────────────────

class _SocialLoginButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onTap;
  final Widget icon;
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color? borderColor;

  const _SocialLoginButton({
    required this.isLoading,
    required this.onTap,
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        height: 52,
        width: double.infinity,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(14),
          border: borderColor != null
              ? Border.all(color: borderColor!, width: 1.5)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: isLoading
            ? Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: foregroundColor.withValues(alpha: 0.6),
                  ),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  icon,
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: GoogleFonts.notoSansTc(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: foregroundColor,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ── Google Icon（用 CustomPaint 畫，不需要額外 asset） ─────────────────────

class _GoogleIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: CustomPaint(painter: _GoogleIconPainter()),
    );
  }
}

class _GoogleIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    final paint = Paint()..style = PaintingStyle.fill;

    // 簡化版 G 形狀（四色弧形）
    const sweepRad = 3.14159265 * 2 / 4;
    final colors = [
      const Color(0xFF4285F4), // Blue
      const Color(0xFF34A853), // Green
      const Color(0xFFFBBC05), // Yellow
      const Color(0xFFEA4335), // Red
    ];

    for (int i = 0; i < 4; i++) {
      paint.color = colors[i];
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -3.14159265 / 2 + sweepRad * i,
        sweepRad,
        true,
        paint,
      );
    }

    // 白色中心遮罩
    paint.color = Colors.white;
    canvas.drawCircle(c, r * 0.6, paint);

    // 白色右側缺口（模擬 G 形狀開口）
    paint.color = Colors.white;
    canvas.drawRect(
      Rect.fromLTWH(c.dx, c.dy - r * 0.25, r, r * 0.5),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
