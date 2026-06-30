import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/clickable.dart';
import '../../../models/profile_model.dart';

class ProfileHeader extends StatelessWidget {
  final ProfileModel profile;
  final VoidCallback onEditTap;

  const ProfileHeader({
    super.key,
    required this.profile,
    required this.onEditTap,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A73E8), Color(0xFF0D47A1)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            children: [
              // Avatar
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  _Avatar(profile: profile),
                  Clickable(
                    onTap: onEditTap,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: AppColors.secondary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.edit_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // Full name
              Text(
                profile.fullName.isEmpty ? 'Your Name' : profile.fullName,
                style: tt.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 6),

              // Phone
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.phone_rounded,
                    size: 13,
                    color: Color(0xCCFFFFFF),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    profile.mobileNumber,
                    style: tt.bodySmall?.copyWith(color: const Color(0xCCFFFFFF)),
                  ),
                ],
              ),

              if (profile.email != null && profile.email!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.email_outlined,
                      size: 13,
                      color: Color(0xCCFFFFFF),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      profile.email!,
                      style: tt.bodySmall?.copyWith(color: const Color(0xCCFFFFFF)),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 18),

              // Edit profile button
              OutlinedButton.icon(
                onPressed: onEditTap,
                icon: const Icon(Icons.edit_outlined, size: 15),
                label: const Text('Edit Profile'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Avatar ────────────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  final ProfileModel profile;

  const _Avatar({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withAlpha(30),
        border: Border.all(color: Colors.white54, width: 2.5),
      ),
      child: profile.imageUrl != null
          ? ClipOval(
              child: Image.network(
                profile.imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _Initials(profile.initials),
              ),
            )
          : _Initials(profile.initials),
    );
  }
}

class _Initials extends StatelessWidget {
  final String text;
  const _Initials(this.text);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 32,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
