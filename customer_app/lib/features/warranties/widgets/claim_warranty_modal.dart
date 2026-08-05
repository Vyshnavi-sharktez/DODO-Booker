import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/my_booking_model.dart';
import '../models/service_warranty_model.dart';
import '../services/warranty_providers.dart';
import '../../bookings/services/bookings_providers.dart';

class ClaimWarrantyModal extends ConsumerStatefulWidget {
  final MyBookingModel booking;
  final ServiceWarrantyModel warranty;

  const ClaimWarrantyModal({
    super.key,
    required this.booking,
    required this.warranty,
  });

  @override
  ConsumerState<ClaimWarrantyModal> createState() => _ClaimWarrantyModalState();
}

class _ClaimWarrantyModalState extends ConsumerState<ClaimWarrantyModal> {
  final _formKey = GlobalKey<FormState>();
  final _issueCtrl = TextEditingController();
  final _picker = ImagePicker();

  final List<String> _photos = [];
  DateTime? _preferredDate;
  bool _submitting = false;
  bool _isUploadingPhoto = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _preferredDate = DateTime.now().add(const Duration(days: 1));
  }

  @override
  void dispose() {
    _issueCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickEvidencePhotos() async {
    if (_isUploadingPhoto) return;

    ImageSource? source;
    if (kIsWeb) {
      source = ImageSource.gallery;
    } else {
      source = await showDialog<ImageSource>(
        context: context,
        builder: (_) => SimpleDialog(
          title: const Text('Add Evidence Photo'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(ImageSource.camera),
              child: const Row(
                children: [
                  Icon(Icons.camera_alt_outlined),
                  SizedBox(width: 12),
                  Text('Take Photo'),
                ],
              ),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(ImageSource.gallery),
              child: const Row(
                children: [
                  Icon(Icons.photo_library_outlined),
                  SizedBox(width: 12),
                  Text('Choose from Gallery'),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (source == null || !mounted) return;

    List<XFile> pickedFiles = [];
    try {
      if (source == ImageSource.gallery && !kIsWeb) {
        pickedFiles = await _picker.pickMultiImage(
          imageQuality: 80,
          maxWidth: 1920,
        );
      } else {
        final single = await _picker.pickImage(
          source: source,
          imageQuality: 80,
          maxWidth: 1920,
        );
        if (single != null) pickedFiles.add(single);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open image picker: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    if (pickedFiles.isEmpty || !mounted) return;

    setState(() => _isUploadingPhoto = true);
    try {
      final client = Supabase.instance.client;
      for (final file in pickedFiles) {
        final bytes = await file.readAsBytes();
        final fileName = '${DateTime.now().millisecondsSinceEpoch}_${_photos.length}.jpg';
        final path = '${widget.booking.id}/warranty_claim_evidence/$fileName';
        await client.storage.from('booking-photos').uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(contentType: file.mimeType ?? 'image/jpeg'),
            );
        final url = client.storage.from('booking-photos').getPublicUrl(path);
        if (mounted) {
          setState(() {
            _photos.add(url);
            _errorMessage = null;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  void _removePhoto(int index) {
    setState(() {
      _photos.removeAt(index);
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _preferredDate ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );
    if (picked != null) {
      setState(() => _preferredDate = picked);
    }
  }

  Future<void> _submitClaim() async {
    if (!widget.warranty.canClaim) {
      setState(() {
        _errorMessage = 'A claim for this warranty is already active, in progress, or resolved.';
      });
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    if (_photos.length < 2) {
      setState(() {
        _errorMessage = 'At least 2 evidence photos are required to submit a warranty claim.';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      final service = ref.read(warrantyServiceProvider);
      final reworkBookingId = await service.submitWarrantyClaim(
        warrantyId: widget.warranty.id,
        bookingId: widget.booking.id,
        customerId: widget.warranty.customerId,
        vendorId: widget.warranty.vendorId,
        issueDescription: _issueCtrl.text,
        photoUrls: _photos,
        preferredDate: _preferredDate,
      );

      // Invalidate Riverpod states
      ref.invalidate(bookingWarrantyProvider(widget.booking.id));
      ref.invalidate(customerWarrantiesProvider);
      ref.invalidate(myBookingsProvider);

      if (!mounted) return;

      Navigator.of(context).pop(reworkBookingId);
    } catch (e) {
      if (!mounted) return;
      debugPrint('[ClaimWarrantyModal] Error submitting claim: $e');
      final msg = e.toString();
      final isCustomerFacing = msg.contains('mandatory') || msg.contains('expired') || msg.contains('claimed');
      setState(() {
        _submitting = false;
        _errorMessage = isCustomerFacing
            ? msg.replaceAll('Exception: ', '')
            : 'Unable to submit warranty claim at this time. Please try again or contact customer support.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFmt = DateFormat('dd MMM yyyy');

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        top: 20,
        left: 20,
        right: 20,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.shield_outlined, color: AppColors.primary, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Claim Service Warranty',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                'Booking #${widget.booking.displayBookingNumber}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),

              const Divider(height: 24),

              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF5F5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFEB2B2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: Color(0xFFE53E3E), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Color(0xFFC53030), fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Issue Description
              Text(
                'Describe the Issue *',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _issueCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Please detail what went wrong or needs rework (min 10 characters)...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.all(12),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Issue description is mandatory.';
                  }
                  if (val.trim().length < 10) {
                    return 'Please provide a detailed description (at least 10 characters).';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Evidence Photos Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Evidence Photos *',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _photos.length >= 2
                          ? const Color(0xFF38A169).withValues(alpha: 0.12)
                          : const Color(0xFFE53E3E).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_photos.length}/2 Attached',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _photos.length >= 2 ? const Color(0xFF38A169) : const Color(0xFFE53E3E),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Real Device Photo Upload Action Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isUploadingPhoto ? null : _pickEvidencePhotos,
                  icon: _isUploadingPhoto
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                        )
                      : const Icon(Icons.add_a_photo_outlined, size: 18),
                  label: Text(_isUploadingPhoto ? 'Uploading Photo...' : 'Add Photos from Device / Gallery'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Photo Thumbnail Grid
              if (_photos.isNotEmpty) ...[
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _photos.asMap().entries.map((entry) {
                    final index = entry.key;
                    final url = entry.value;
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            url,
                            width: 72,
                            height: 72,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 72,
                              height: 72,
                              color: Colors.grey.shade200,
                              child: const Icon(Icons.broken_image_rounded, size: 24, color: Colors.grey),
                            ),
                          ),
                        ),
                        Positioned(
                          top: -6,
                          right: -6,
                          child: GestureDetector(
                            onTap: () => _removePhoto(index),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: AppColors.error,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ] else ...[
                Text(
                  'Please select at least 2 photos from your device demonstrating the issue.',
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.error, fontSize: 12),
                ),
              ],

              const SizedBox(height: 20),

              // Preferred Rework Service Date
              Text(
                'Preferred Rework Date',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded, size: 18, color: AppColors.primary),
                      const SizedBox(width: 10),
                      Text(
                        _preferredDate != null ? dateFmt.format(_preferredDate!) : 'Select preferred date',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                      const Spacer(),
                      const Icon(Icons.edit_calendar_rounded, size: 18, color: AppColors.textSecondary),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Submit Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: _submitting ? null : _submitClaim,
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.shield_rounded, size: 20),
                  label: Text(
                    _submitting ? 'Submitting Claim...' : 'Submit Warranty Claim',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF38A169),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
