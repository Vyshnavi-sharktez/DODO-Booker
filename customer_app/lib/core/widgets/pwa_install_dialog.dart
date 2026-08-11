import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../services/pwa_install_service.dart';

enum _DialogPhase { idle, installing, accepted, unavailable }

class PwaInstallDialog extends StatefulWidget {
  const PwaInstallDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withAlpha(80),
      builder: (_) => const PwaInstallDialog(),
    );
  }

  @override
  State<PwaInstallDialog> createState() => _PwaInstallDialogState();
}

class _PwaInstallDialogState extends State<PwaInstallDialog> {
  final _service = PwaInstallService();
  late _DialogPhase _phase;

  @override
  void initState() {
    super.initState();
    _phase = switch (_service.state) {
      PwaInstallState.alreadyInstalled => _DialogPhase.accepted,
      PwaInstallState.available => _DialogPhase.idle,
      PwaInstallState.unavailable => _DialogPhase.unavailable,
    };
  }

  Future<void> _install() async {
    setState(() => _phase = _DialogPhase.installing);
    final accepted = await _service.triggerInstall();
    if (!mounted) return;
    setState(() => _phase = accepted ? _DialogPhase.accepted : _DialogPhase.idle);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 28, 28, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Close button
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.close_rounded,
                        size: 16, color: AppColors.textSecondary),
                  ),
                ),
              ),
              const SizedBox(height: 4),

              // App icon
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.textPrimary,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.home_repair_service_rounded,
                  color: AppColors.gold,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),

              // App name
              const Text(
                'DODO Booker',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 6),

              // Tagline
              const Text(
                'Get DODO on your device',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              const Text(
                'Install DODO Booker and use it like an app.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textHint,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),

              // Primary action
              _buildPrimaryArea(context),

              const SizedBox(height: 16),

              // Continue on web
              if (_phase != _DialogPhase.accepted)
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'Already using DODO? ',
                            style: TextStyle(
                                fontSize: 12.5, color: AppColors.textHint),
                          ),
                          TextSpan(
                            text: 'Continue on web →',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.underline,
                              decorationColor: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPrimaryArea(BuildContext context) {
    switch (_phase) {
      case _DialogPhase.idle:
        return _InstallButton(onTap: _install);

      case _DialogPhase.installing:
        return Container(
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            color: AppColors.textPrimary,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          ),
        );

      case _DialogPhase.accepted:
        return Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                color: Color(0xFF1A8A4A),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded,
                  color: Colors.white, size: 26),
            ),
            const SizedBox(height: 12),
            const Text(
              'DODO Booker is installed!',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            const Text(
              'Find it on your home screen or app drawer.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            _OutlineButton(
              label: 'Done',
              onTap: () => Navigator.pop(context),
            ),
          ],
        );

      case _DialogPhase.unavailable:
        return Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border, width: 0.8),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 16, color: AppColors.textSecondary),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Installation is not available in this browser. '
                      'Try opening DODO Booker in Chrome on Android, '
                      'or Safari on iOS, to install it.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _OutlineButton(
              label: 'Continue on web →',
              onTap: () => Navigator.pop(context),
            ),
          ],
        );
    }
  }
}

class _InstallButton extends StatefulWidget {
  final VoidCallback onTap;
  const _InstallButton({required this.onTap});

  @override
  State<_InstallButton> createState() => _InstallButtonState();
}

class _InstallButtonState extends State<_InstallButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            color: _hovered ? const Color(0xFF2A2A2A) : AppColors.textPrimary,
            borderRadius: BorderRadius.circular(14),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: Colors.black.withAlpha(50),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.download_rounded, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text(
                'Install DODO',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OutlineButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _OutlineButton({required this.label, required this.onTap});

  @override
  State<_OutlineButton> createState() => _OutlineButtonState();
}

class _OutlineButtonState extends State<_OutlineButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          height: 44,
          decoration: BoxDecoration(
            color: _hovered ? AppColors.surfaceVariant : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border, width: 1),
          ),
          child: Center(
            child: Text(
              widget.label,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
