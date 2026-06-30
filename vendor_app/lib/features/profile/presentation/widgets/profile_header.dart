import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/clickable.dart';
import '../../../auth/presentation/providers/auth_controller.dart';
import '../../domain/models/vendor_profile.dart';
import '../providers/profile_provider.dart';

class ProfileHeader extends ConsumerStatefulWidget {
  const ProfileHeader({super.key, required this.profile});
  final VendorProfile profile;

  @override
  ConsumerState<ProfileHeader> createState() => _ProfileHeaderState();
}

class _ProfileHeaderState extends ConsumerState<ProfileHeader> {
  bool _uploading = false;

  Future<void> _pickAndUpload() async {
    final vendor = ref.read(currentVendorUserProvider);
    if (vendor == null) return;

    final XFile? file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;

    final ext = file.name.split('.').last.toLowerCase();
    if (!{'jpg', 'jpeg', 'png', 'webp'}.contains(ext)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unsupported format. Use jpg, jpeg, png or webp.'),
          ),
        );
      }
      return;
    }

    final contentType = switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };

    setState(() => _uploading = true);
    try {
      final bytes = await file.readAsBytes();
      await ref.read(uploadProfilePhotoUseCaseProvider)(
        vendorId: vendor.id,
        bytes: bytes,
        contentType: contentType,
      );
      ref.invalidate(vendorProfileProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile photo updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final initials = _initials(profile.businessName);
    final imageUrl = profile.profileImageUrl;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Tooltip(
            message: 'Change Profile Photo',
            child: Clickable(
              onTap: _uploading ? null : _pickAndUpload,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: AppColors.primaryLight,
                    backgroundImage:
                        imageUrl != null ? NetworkImage(imageUrl) : null,
                    child: imageUrl == null
                        ? Text(
                            initials,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          )
                        : null,
                  ),
                  if (_uploading)
                    const Positioned.fill(
                      child: CircleAvatar(
                        radius: 40,
                        backgroundColor: Colors.black45,
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        size: 18,
                        color: AppColors.primary,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap photo to change',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white60,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            profile.businessName,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
          ),
          if (profile.ownerName != null && profile.ownerName!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              profile.ownerName!,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.white70),
            ),
          ],
          const SizedBox(height: 12),
          _StatusChip(status: profile.status, isActive: profile.isActive),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.isActive});
  final String status;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppColors.success : AppColors.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isActive ? const Color(0x3334A853) : const Color(0x33EA4335),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isActive ? Icons.check_circle_outline : Icons.cancel_outlined,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            status.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
