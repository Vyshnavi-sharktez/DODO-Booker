import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/models/landing_page_section.dart';
import '../../domain/models/section_type.dart';

// ── Icon choices available for admin dropdowns ────────────────────────────────

const _kIconOptions = <({String name, String label})>[
  (name: 'verified_user_rounded',       label: 'Verified User'),
  (name: 'receipt_long_rounded',        label: 'Receipt / Pricing'),
  (name: 'lock_rounded',                label: 'Lock / Security'),
  (name: 'search_rounded',              label: 'Search'),
  (name: 'access_time_rounded',         label: 'Clock / Time'),
  (name: 'check_circle_rounded',        label: 'Check Circle'),
  (name: 'star_rounded',                label: 'Star'),
  (name: 'home_rounded',                label: 'Home'),
  (name: 'build_rounded',               label: 'Build / Tool'),
  (name: 'handyman_rounded',            label: 'Handyman'),
  (name: 'cleaning_services_rounded',   label: 'Cleaning'),
  (name: 'electrical_services_rounded', label: 'Electrical'),
  (name: 'plumbing_rounded',            label: 'Plumbing'),
  (name: 'air_rounded',                 label: 'AC / Air'),
  (name: 'carpenter_rounded',           label: 'Carpenter'),
  (name: 'support_agent_rounded',       label: 'Support'),
  (name: 'thumb_up_rounded',            label: 'Thumb Up'),
  (name: 'shield_rounded',              label: 'Shield'),
  (name: 'local_offer_rounded',         label: 'Offer / Tag'),
  (name: 'payment_rounded',             label: 'Payment'),
  (name: 'calendar_today_rounded',      label: 'Calendar'),
  (name: 'bolt_rounded',                label: 'Speed / Bolt'),
  (name: 'person_search_rounded',       label: 'Person Search'),
  (name: 'rocket_launch_rounded',       label: 'Launch / Fast'),
  (name: 'workspace_premium_rounded',   label: 'Premium'),
];

// ── Supabase Storage bucket for CMS media ─────────────────────────────────────
// Create a public bucket named 'cms-media' in Supabase Storage before uploading.
const _kCmsMediaBucket = 'cms-media';

// ── Entry point ───────────────────────────────────────────────────────────────

class SectionEditDialog extends StatefulWidget {
  const SectionEditDialog({super.key, required this.section});
  final LandingPageSection section;

  @override
  State<SectionEditDialog> createState() => _SectionEditDialogState();
}

class _SectionEditDialogState extends State<SectionEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late Map<String, dynamic> _config;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.section.sectionName);
    _config = Map<String, dynamic>.from(widget.section.config);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop((
      sectionName: _nameCtrl.text.trim(),
      config: _config,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final sectionType = SectionType.fromDbKey(widget.section.sectionType);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Fixed header ───────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        sectionType?.icon ?? Icons.widgets_rounded,
                        color: AppColors.primary,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Edit Section',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            sectionType?.displayName ??
                                widget.section.sectionType,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // ── Scrollable form body ───────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Section name (always shown)
                      _label('SECTION NAME'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                            hintText: 'e.g. Why Choose DODO'),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 24),

                      // Type-specific config
                      _ConfigEditor(
                        sectionType: widget.section.sectionType,
                        config: _config,
                        onChanged: (updated) =>
                            setState(() => _config = updated),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),

              // ── Fixed action bar ───────────────────────────────────────
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                      ),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                      ),
                      child: const Text('Save Changes'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Config editor dispatcher ──────────────────────────────────────────────────

class _ConfigEditor extends StatelessWidget {
  const _ConfigEditor({
    required this.sectionType,
    required this.config,
    required this.onChanged,
  });
  final String sectionType;
  final Map<String, dynamic> config;
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  Widget build(BuildContext context) {
    final typeWidget = switch (sectionType) {
      'hero'             => _HeroConfig(config: config, onChanged: onChanged),
      'service_grid'     => _TitleWithToggleConfig(config: config, onChanged: onChanged, titleHint: 'Our Services'),
      'sub_services'     => _TitleOnlyConfig(config: config, onChanged: onChanged, titleHint: 'Sub Services'),
      'why_dodo'         => _WhyDodoConfig(config: config, onChanged: onChanged),
      'how_it_works'     => _HowItWorksConfig(config: config, onChanged: onChanged),
      'special_offers'   => _SpecialOffersConfig(config: config, onChanged: onChanged),
      'popular_near_you' => _TitleWithToggleConfig(config: config, onChanged: onChanged, titleHint: 'Popular Near You'),
      'testimonials'     => _TestimonialsConfig(config: config, onChanged: onChanged),
      'footer'           => _FooterConfig(config: config, onChanged: onChanged),
      'content_grid'     => _ContentGridConfig(config: config, onChanged: onChanged),
      'promo_banner'     => _PromoBannerConfig(config: config, onChanged: onChanged),
      'faq'              => _FaqConfig(config: config, onChanged: onChanged),
      'cta'              => _CtaConfig(config: config, onChanged: onChanged),
      _                  => const SizedBox.shrink(),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        typeWidget,
        const SizedBox(height: 24),
        const Divider(height: 1),
        const SizedBox(height: 20),
        _SectionMediaBlock(config: config, onChanged: onChanged),
      ],
    );
  }
}

// ── Universal media block (available on every section type) ──────────────────
//
// Stores under config['media']:
//   { 'type': 'none'|'image'|'video',
//     'image_url': '...', 'video_url': '...', 'poster_url': '...' }
//
// Customer-App renderers are free to use or ignore this field based on the
// section's approved visual design.

class _SectionMediaBlock extends StatefulWidget {
  const _SectionMediaBlock({required this.config, required this.onChanged});
  final Map<String, dynamic> config;
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  State<_SectionMediaBlock> createState() => _SectionMediaBlockState();
}

class _SectionMediaBlockState extends State<_SectionMediaBlock> {
  late String _type; // 'none' | 'image' | 'video'

  Map<String, dynamic> get _media =>
      Map<String, dynamic>.from((widget.config['media'] as Map?) ?? {});

  @override
  void initState() {
    super.initState();
    final m = widget.config['media'] as Map?;
    _type = (m?['type'] as String?) ?? 'none';
  }

  void _setType(String t) {
    setState(() => _type = t);
    final m = _media;
    m['type'] = t;
    widget.onChanged({...widget.config, 'media': m});
  }

  void _setField(String field, String value) {
    final m = _media;
    m['type'] = _type;
    m[field] = value;
    widget.onChanged({...widget.config, 'media': m});
  }

  @override
  Widget build(BuildContext context) {
    final m = _media;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('SECTION MEDIA'),
        const SizedBox(height: 10),

        // ── None / Image / Video toggle ────────────────────────────────
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'none',  label: Text('None')),
            ButtonSegment(value: 'image', label: Text('Image')),
            ButtonSegment(value: 'video', label: Text('Video')),
          ],
          selected: {_type},
          onSelectionChanged: (s) => _setType(s.first),
          style: SegmentedButton.styleFrom(
            textStyle: const TextStyle(fontSize: 12),
            minimumSize: const Size(0, 34),
          ),
        ),

        if (_type == 'image') ...[
          const SizedBox(height: 16),
          _CmsMediaPicker(
            label: 'IMAGE',
            value: m['image_url'] as String? ?? '',
            onChanged: (v) => _setField('image_url', v),
          ),
        ],

        if (_type == 'video') ...[
          const SizedBox(height: 16),
          _CmsMediaPicker(
            label: 'VIDEO',
            value: m['video_url'] as String? ?? '',
            hint: 'https://... or upload MP4/WebM',
            acceptVideo: true,
            onChanged: (v) => _setField('video_url', v),
          ),
          const SizedBox(height: 14),
          _CmsMediaPicker(
            label: 'POSTER / THUMBNAIL',
            value: m['poster_url'] as String? ?? '',
            hint: 'Optional still image shown before playback',
            onChanged: (v) => _setField('poster_url', v),
          ),
        ],
      ],
    );
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

Widget _label(String text) => Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppColors.textSecondary,
        letterSpacing: 0.8,
      ),
    );

Widget _infoBox(String message) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                  fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );

// ── Shared media picker field ─────────────────────────────────────────────────
// Supports URL input and upload to Supabase Storage bucket 'cms-media'.

class _CmsMediaPicker extends StatefulWidget {
  const _CmsMediaPicker({
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint = 'https://... or click Upload',
    this.acceptVideo = false,
  });
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final String hint;
  final bool acceptVideo;

  @override
  State<_CmsMediaPicker> createState() => _CmsMediaPickerState();
}

class _CmsMediaPickerState extends State<_CmsMediaPicker> {
  late final TextEditingController _ctrl;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _upload() async {
    final result = await FilePicker.platform.pickFiles(
      type: widget.acceptVideo ? FileType.media : FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;

    final ext = (file.extension ?? 'jpg').toLowerCase();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = 'cms/$ts.${file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')}';

    setState(() => _uploading = true);
    try {
      await Supabase.instance.client.storage
          .from(_kCmsMediaBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: _mimeFor(ext), upsert: true),
          );
      final url = Supabase.instance.client.storage
          .from(_kCmsMediaBucket)
          .getPublicUrl(path);
      if (mounted) {
        setState(() {
          _ctrl.text = url;
          _uploading = false;
        });
        widget.onChanged(url);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Upload failed. Ensure a public bucket named '
              '"$_kCmsMediaBucket" exists in Supabase Storage.\n$e',
            ),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }
  }

  static String _mimeFor(String ext) {
    const map = {
      'jpg': 'image/jpeg', 'jpeg': 'image/jpeg',
      'png': 'image/png', 'gif': 'image/gif', 'webp': 'image/webp',
      'mp4': 'video/mp4', 'webm': 'video/webm', 'mov': 'video/quicktime',
    };
    return map[ext] ?? 'application/octet-stream';
  }

  void _clear() {
    setState(() => _ctrl.text = '');
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final hasUrl = _ctrl.text.isNotEmpty;
    final isImage = hasUrl &&
        (widget.acceptVideo == false ||
            !_ctrl.text.split('.').last.toLowerCase().contains(
                RegExp(r'mp4|webm|mov')));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label.isNotEmpty) ...[
          _label(widget.label),
          const SizedBox(height: 6),
        ],
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _ctrl,
                onChanged: widget.onChanged,
                decoration: InputDecoration(
                  hintText: widget.hint,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              height: 42,
              child: _uploading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.accent),
                      ),
                    )
                  : OutlinedButton.icon(
                      onPressed: _upload,
                      icon: const Icon(Icons.upload_rounded, size: 14),
                      label: const Text('Upload'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        foregroundColor: AppColors.accent,
                        side: const BorderSide(color: AppColors.border),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
            ),
            if (hasUrl) ...[
              const SizedBox(width: 4),
              SizedBox(
                width: 34,
                height: 42,
                child: IconButton(
                  onPressed: _clear,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  tooltip: 'Remove',
                  style: IconButton.styleFrom(
                    foregroundColor: AppColors.error,
                    minimumSize: Size.zero,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ],
        ),
        // Thumbnail preview for image URLs
        if (hasUrl && isImage) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.network(
              _ctrl.text,
              height: 80,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Hero ──────────────────────────────────────────────────────────────────────

class _HeroConfig extends StatefulWidget {
  const _HeroConfig({required this.config, required this.onChanged});
  final Map<String, dynamic> config;
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  State<_HeroConfig> createState() => _HeroConfigState();
}

class _HeroConfigState extends State<_HeroConfig> {
  late final TextEditingController _headline;
  late final TextEditingController _subheadline;
  late final TextEditingController _ctaPrimary;
  late final TextEditingController _ctaSecondary;

  @override
  void initState() {
    super.initState();
    _headline = TextEditingController(
        text: widget.config['headline'] as String? ?? '');
    _subheadline = TextEditingController(
        text: widget.config['subheadline'] as String? ?? '');
    _ctaPrimary = TextEditingController(
        text: widget.config['cta_primary_text'] as String? ?? 'Book Now');
    _ctaSecondary = TextEditingController(
        text: widget.config['cta_secondary_text'] as String? ?? 'Explore Services');
  }

  @override
  void dispose() {
    _headline.dispose();
    _subheadline.dispose();
    _ctaPrimary.dispose();
    _ctaSecondary.dispose();
    super.dispose();
  }

  void _notify() {
    widget.onChanged({
      ...widget.config,
      'headline': _headline.text,
      'subheadline': _subheadline.text,
      'cta_primary_text': _ctaPrimary.text,
      'cta_secondary_text': _ctaSecondary.text,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Text content ──────────────────────────────────────────────
        _label('HEADLINE'),
        const SizedBox(height: 6),
        TextFormField(
          controller: _headline,
          onChanged: (_) => _notify(),
          decoration: const InputDecoration(
              hintText: 'Expert Home Services, On Demand'),
        ),
        const SizedBox(height: 16),
        _label('SUB-HEADLINE'),
        const SizedBox(height: 6),
        TextFormField(
          controller: _subheadline,
          maxLines: 2,
          onChanged: (_) => _notify(),
          decoration: const InputDecoration(
              hintText:
                  'Trusted professionals for all your home needs...'),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('PRIMARY CTA'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _ctaPrimary,
                    onChanged: (_) => _notify(),
                    decoration:
                        const InputDecoration(hintText: 'Book Now'),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('SECONDARY CTA'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _ctaSecondary,
                    onChanged: (_) => _notify(),
                    decoration: const InputDecoration(
                        hintText: 'Explore Services'),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // ── Media ─────────────────────────────────────────────────────
        _label('DESKTOP BACKGROUND IMAGE'),
        const SizedBox(height: 2),
        Text(
          'Shown behind the hero on large screens (recommended: 1440×720 px).',
          style: const TextStyle(
              fontSize: 11, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 6),
        _CmsMediaPicker(
          label: '',
          value: widget.config['desktop_image_url'] as String? ?? '',
          onChanged: (v) => widget.onChanged(
              {...widget.config, 'desktop_image_url': v}),
        ),
        const SizedBox(height: 16),

        _label('MOBILE BACKGROUND IMAGE'),
        const SizedBox(height: 2),
        Text(
          'Shown behind the hero on small screens (recommended: 390×480 px).',
          style: const TextStyle(
              fontSize: 11, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 6),
        _CmsMediaPicker(
          label: '',
          value: widget.config['mobile_image_url'] as String? ?? '',
          onChanged: (v) => widget.onChanged(
              {...widget.config, 'mobile_image_url': v}),
        ),
        const SizedBox(height: 16),

        _label('DESKTOP BACKGROUND VIDEO (optional)'),
        const SizedBox(height: 2),
        Text(
          'Auto-playing background video on desktop. Image used as poster/fallback.',
          style: const TextStyle(
              fontSize: 11, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 6),
        _CmsMediaPicker(
          label: '',
          value: widget.config['desktop_video_url'] as String? ?? '',
          hint: 'https://... or upload MP4/WebM',
          acceptVideo: true,
          onChanged: (v) => widget.onChanged(
              {...widget.config, 'desktop_video_url': v}),
        ),
      ],
    );
  }
}

// ── Title only ────────────────────────────────────────────────────────────────

class _TitleOnlyConfig extends StatefulWidget {
  const _TitleOnlyConfig({
    required this.config,
    required this.onChanged,
    required this.titleHint,
  });
  final Map<String, dynamic> config;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final String titleHint;

  @override
  State<_TitleOnlyConfig> createState() => _TitleOnlyConfigState();
}

class _TitleOnlyConfigState extends State<_TitleOnlyConfig> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
        text: widget.config['title'] as String? ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('SECTION TITLE'),
        const SizedBox(height: 6),
        TextFormField(
          controller: _ctrl,
          onChanged: (v) =>
              widget.onChanged({...widget.config, 'title': v}),
          decoration: InputDecoration(hintText: widget.titleHint),
        ),
      ],
    );
  }
}

// ── Title + Show See All toggle ───────────────────────────────────────────────

class _TitleWithToggleConfig extends StatefulWidget {
  const _TitleWithToggleConfig({
    required this.config,
    required this.onChanged,
    required this.titleHint,
  });
  final Map<String, dynamic> config;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final String titleHint;

  @override
  State<_TitleWithToggleConfig> createState() =>
      _TitleWithToggleConfigState();
}

class _TitleWithToggleConfigState extends State<_TitleWithToggleConfig> {
  late final TextEditingController _titleCtrl;
  late bool _showSeeAll;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(
        text: widget.config['title'] as String? ?? '');
    _showSeeAll = widget.config['show_see_all'] as bool? ?? true;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  void _notify() {
    widget.onChanged({
      ...widget.config,
      'title': _titleCtrl.text,
      'show_see_all': _showSeeAll,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('SECTION TITLE'),
        const SizedBox(height: 6),
        TextFormField(
          controller: _titleCtrl,
          onChanged: (_) => _notify(),
          decoration: InputDecoration(hintText: widget.titleHint),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Switch(
              value: _showSeeAll,
              onChanged: (v) {
                setState(() => _showSeeAll = v);
                _notify();
              },
              activeThumbColor: AppColors.accent,
            ),
            const SizedBox(width: 8),
            const Text(
              'Show "See All" link',
              style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Special Offers ────────────────────────────────────────────────────────────

class _SpecialOffersConfig extends StatefulWidget {
  const _SpecialOffersConfig(
      {required this.config, required this.onChanged});
  final Map<String, dynamic> config;
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  State<_SpecialOffersConfig> createState() => _SpecialOffersConfigState();
}

class _SpecialOffersConfigState extends State<_SpecialOffersConfig> {
  late final TextEditingController _titleCtrl;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(
        text: widget.config['title'] as String? ?? 'Special Offers');
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('SECTION TITLE'),
        const SizedBox(height: 6),
        TextFormField(
          controller: _titleCtrl,
          onChanged: (v) =>
              widget.onChanged({...widget.config, 'title': v}),
          decoration:
              const InputDecoration(hintText: 'Special Offers'),
        ),
        const SizedBox(height: 16),
        _infoBox(
          'Coupon cards are sourced automatically from active coupons in '
          'the database. No additional data-source configuration is needed.',
        ),
      ],
    );
  }
}

// ── Testimonials / Customer Reviews ───────────────────────────────────────────

class _TestimonialsConfig extends StatefulWidget {
  const _TestimonialsConfig(
      {required this.config, required this.onChanged});
  final Map<String, dynamic> config;
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  State<_TestimonialsConfig> createState() => _TestimonialsConfigState();
}

class _TestimonialsConfigState extends State<_TestimonialsConfig> {
  late final TextEditingController _titleCtrl;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(
        text: widget.config['title'] as String? ??
            'What Our Customers Say');
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('SECTION TITLE'),
        const SizedBox(height: 6),
        TextFormField(
          controller: _titleCtrl,
          onChanged: (v) =>
              widget.onChanged({...widget.config, 'title': v}),
          decoration: const InputDecoration(
              hintText: 'What Our Customers Say'),
        ),
        const SizedBox(height: 16),
        _infoBox(
          'Reviews are sourced automatically from verified customer '
          'bookings. No additional data-source configuration is needed.',
        ),
      ],
    );
  }
}

// ── Footer ────────────────────────────────────────────────────────────────────

class _FooterConfig extends StatefulWidget {
  const _FooterConfig({required this.config, required this.onChanged});
  final Map<String, dynamic> config;
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  State<_FooterConfig> createState() => _FooterConfigState();
}

class _FooterConfigState extends State<_FooterConfig> {
  late final TextEditingController _copyrightCtrl;

  @override
  void initState() {
    super.initState();
    _copyrightCtrl = TextEditingController(
        text: widget.config['copyright_text'] as String? ?? '');
  }

  @override
  void dispose() {
    _copyrightCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('COPYRIGHT TEXT'),
        const SizedBox(height: 6),
        TextFormField(
          controller: _copyrightCtrl,
          onChanged: (v) => widget
              .onChanged({...widget.config, 'copyright_text': v}),
          decoration: const InputDecoration(
            hintText: '© 2025 DODO Booker. All rights reserved.',
          ),
        ),
        const SizedBox(height: 16),
        _infoBox(
          'Footer navigation links and social icons are managed in the '
          'app codebase. This section controls the copyright notice text.',
        ),
      ],
    );
  }
}

// ── Why DODO items list ───────────────────────────────────────────────────────

class _WhyDodoConfig extends StatefulWidget {
  const _WhyDodoConfig({required this.config, required this.onChanged});
  final Map<String, dynamic> config;
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  State<_WhyDodoConfig> createState() => _WhyDodoConfigState();
}

class _WhyDodoConfigState extends State<_WhyDodoConfig> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _subtitleCtrl;
  late List<Map<String, dynamic>> _items;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(
        text: widget.config['title'] as String? ?? '');
    _subtitleCtrl = TextEditingController(
        text: widget.config['subtitle'] as String? ?? '');
    _items = ((widget.config['items'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
    super.dispose();
  }

  void _notify() {
    widget.onChanged({
      ...widget.config,
      'title': _titleCtrl.text,
      'subtitle': _subtitleCtrl.text,
      'items': _items,
    });
  }

  void _addItem() {
    setState(() => _items.add({
          'icon': 'star_rounded',
          'title': 'New Item',
          'description': '',
        }));
    _notify();
  }

  void _removeItem(int i) {
    setState(() => _items.removeAt(i));
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('SECTION TITLE'),
        const SizedBox(height: 6),
        TextFormField(
          controller: _titleCtrl,
          onChanged: (_) => _notify(),
          decoration:
              const InputDecoration(hintText: 'Why Choose DODO Booker?'),
        ),
        const SizedBox(height: 14),
        _label('SUB-HEADING'),
        const SizedBox(height: 6),
        TextFormField(
          controller: _subtitleCtrl,
          onChanged: (_) => _notify(),
          decoration: const InputDecoration(
              hintText: 'Everything you need for a seamless experience.'),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            _label('TRUST ITEMS'),
            const Spacer(),
            TextButton.icon(
              onPressed: _addItem,
              icon: const Icon(Icons.add_rounded, size: 14),
              label: const Text('Add Item'),
              style: TextButton.styleFrom(
                  textStyle: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._items.asMap().entries.map((entry) {
          final i = entry.key;
          return _ItemRow(
            key: ValueKey('why-$i'),
            item: entry.value,
            iconLabel: 'Icon',
            titleLabel: 'Title',
            descLabel: 'Description',
            onChanged: (updated) {
              setState(() => _items[i] = updated);
              _notify();
            },
            onDelete: () => _removeItem(i),
          );
        }),
      ],
    );
  }
}

// ── How It Works steps list ───────────────────────────────────────────────────

class _HowItWorksConfig extends StatefulWidget {
  const _HowItWorksConfig({required this.config, required this.onChanged});
  final Map<String, dynamic> config;
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  State<_HowItWorksConfig> createState() => _HowItWorksConfigState();
}

class _HowItWorksConfigState extends State<_HowItWorksConfig> {
  late final TextEditingController _titleCtrl;
  late List<Map<String, dynamic>> _steps;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(
        text: widget.config['title'] as String? ?? '');
    _steps = ((widget.config['steps'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  void _notify() {
    widget.onChanged({
      ...widget.config,
      'title': _titleCtrl.text,
      'steps': _steps,
    });
  }

  void _addStep() {
    setState(() => _steps.add({
          'icon': 'search_rounded',
          'title': 'New Step',
          'description': '',
        }));
    _notify();
  }

  void _removeStep(int i) {
    setState(() => _steps.removeAt(i));
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('SECTION TITLE'),
        const SizedBox(height: 6),
        TextFormField(
          controller: _titleCtrl,
          onChanged: (_) => _notify(),
          decoration:
              const InputDecoration(hintText: 'How DODO Booker Works'),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            _label('STEPS'),
            const Spacer(),
            TextButton.icon(
              onPressed: _addStep,
              icon: const Icon(Icons.add_rounded, size: 14),
              label: const Text('Add Step'),
              style: TextButton.styleFrom(
                  textStyle: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._steps.asMap().entries.map((entry) {
          final i = entry.key;
          return _ItemRow(
            key: ValueKey('step-$i'),
            item: entry.value,
            iconLabel: 'Icon',
            titleLabel: 'Step Title',
            descLabel: 'Description',
            onChanged: (updated) {
              setState(() => _steps[i] = updated);
              _notify();
            },
            onDelete: () => _removeStep(i),
          );
        }),
      ],
    );
  }
}

// ── Generic item row (icon + title + description + delete) ───────────────────

class _ItemRow extends StatefulWidget {
  const _ItemRow({
    super.key,
    required this.item,
    required this.iconLabel,
    required this.titleLabel,
    required this.descLabel,
    required this.onChanged,
    required this.onDelete,
  });
  final Map<String, dynamic> item;
  final String iconLabel;
  final String titleLabel;
  final String descLabel;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final VoidCallback onDelete;

  @override
  State<_ItemRow> createState() => _ItemRowState();
}

class _ItemRowState extends State<_ItemRow> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late String _selectedIcon;

  @override
  void initState() {
    super.initState();
    _titleCtrl =
        TextEditingController(text: widget.item['title'] as String? ?? '');
    _descCtrl = TextEditingController(
        text: widget.item['description'] as String? ?? '');
    _selectedIcon =
        widget.item['icon'] as String? ?? _kIconOptions.first.name;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _notify() {
    widget.onChanged({
      ...widget.item,
      'icon': _selectedIcon,
      'title': _titleCtrl.text,
      'description': _descCtrl.text,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _kIconOptions.any((o) => o.name == _selectedIcon)
                      ? _selectedIcon
                      : _kIconOptions.first.name,
                  decoration: InputDecoration(
                    labelText: widget.iconLabel,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                  items: _kIconOptions
                      .map((o) => DropdownMenuItem(
                            value: o.name,
                            child: Text(o.label,
                                style: const TextStyle(fontSize: 12)),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _selectedIcon = v);
                    _notify();
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: widget.onDelete,
                icon: const Icon(Icons.delete_outline_rounded,
                    size: 16, color: AppColors.error),
                tooltip: 'Remove',
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _titleCtrl,
            onChanged: (_) => _notify(),
            decoration: InputDecoration(
              labelText: widget.titleLabel,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _descCtrl,
            maxLines: 2,
            onChanged: (_) => _notify(),
            decoration: InputDecoration(
              labelText: widget.descLabel,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Content Grid config ───────────────────────────────────────────────────────

class _ContentGridConfig extends StatefulWidget {
  const _ContentGridConfig({required this.config, required this.onChanged});
  final Map<String, dynamic> config;
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  State<_ContentGridConfig> createState() => _ContentGridConfigState();
}

class _ContentGridConfigState extends State<_ContentGridConfig> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _subtitleCtrl;
  late List<Map<String, dynamic>> _items;

  @override
  void initState() {
    super.initState();
    _titleCtrl =
        TextEditingController(text: widget.config['title'] as String? ?? '');
    _subtitleCtrl = TextEditingController(
        text: widget.config['subtitle'] as String? ?? '');
    _items = ((widget.config['items'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
    super.dispose();
  }

  void _notify() {
    widget.onChanged({
      ...widget.config,
      'title': _titleCtrl.text,
      'subtitle': _subtitleCtrl.text,
      'items': _items,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('TITLE'),
        const SizedBox(height: 6),
        TextFormField(
          controller: _titleCtrl,
          onChanged: (_) => _notify(),
          decoration:
              const InputDecoration(hintText: 'Thoughtful Creations'),
        ),
        const SizedBox(height: 14),
        _label('SUBTITLE'),
        const SizedBox(height: 6),
        TextFormField(
          controller: _subtitleCtrl,
          onChanged: (_) => _notify(),
          decoration: const InputDecoration(
              hintText: 'Curated services for your home.'),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            _label('ITEMS'),
            const Spacer(),
            TextButton.icon(
              onPressed: () {
                setState(() => _items
                    .add({'image_url': '', 'title': '', 'description': ''}));
                _notify();
              },
              icon: const Icon(Icons.add_rounded, size: 14),
              label: const Text('Add Item'),
              style: TextButton.styleFrom(
                  textStyle: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._items.asMap().entries.map((entry) {
          final i = entry.key;
          final item = entry.value;
          return _ContentGridItemRow(
            key: ValueKey('cgi-$i'),
            item: item,
            onChanged: (updated) {
              setState(() => _items[i] = updated);
              _notify();
            },
            onDelete: () {
              setState(() => _items.removeAt(i));
              _notify();
            },
          );
        }),
      ],
    );
  }
}

class _ContentGridItemRow extends StatefulWidget {
  const _ContentGridItemRow({
    super.key,
    required this.item,
    required this.onChanged,
    required this.onDelete,
  });
  final Map<String, dynamic> item;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final VoidCallback onDelete;

  @override
  State<_ContentGridItemRow> createState() => _ContentGridItemRowState();
}

class _ContentGridItemRowState extends State<_ContentGridItemRow> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;

  @override
  void initState() {
    super.initState();
    _titleCtrl =
        TextEditingController(text: widget.item['title'] as String? ?? '');
    _descCtrl = TextEditingController(
        text: widget.item['description'] as String? ?? '');
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _notify(String imageUrl) {
    widget.onChanged({
      'image_url': imageUrl,
      'title': _titleCtrl.text,
      'description': _descCtrl.text,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _CmsMediaPicker(
                  label: 'IMAGE',
                  value: widget.item['image_url'] as String? ?? '',
                  onChanged: (v) => _notify(v),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: widget.onDelete,
                icon: const Icon(Icons.delete_outline_rounded,
                    size: 16, color: AppColors.error),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _titleCtrl,
            onChanged: (_) => _notify(widget.item['image_url'] as String? ?? ''),
            decoration: const InputDecoration(
              labelText: 'Title',
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _descCtrl,
            onChanged: (_) => _notify(widget.item['image_url'] as String? ?? ''),
            decoration: const InputDecoration(
              labelText: 'Description',
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Promo Banner config ───────────────────────────────────────────────────────

class _PromoBannerConfig extends StatefulWidget {
  const _PromoBannerConfig({required this.config, required this.onChanged});
  final Map<String, dynamic> config;
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  State<_PromoBannerConfig> createState() => _PromoBannerConfigState();
}

class _PromoBannerConfigState extends State<_PromoBannerConfig> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _subtitleCtrl;
  late final TextEditingController _ctaCtrl;

  @override
  void initState() {
    super.initState();
    _titleCtrl =
        TextEditingController(text: widget.config['title'] as String? ?? '');
    _subtitleCtrl = TextEditingController(
        text: widget.config['subtitle'] as String? ?? '');
    _ctaCtrl = TextEditingController(
        text: widget.config['cta_text'] as String? ?? '');
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
    _ctaCtrl.dispose();
    super.dispose();
  }

  void _notify() {
    widget.onChanged({
      ...widget.config,
      'title': _titleCtrl.text,
      'subtitle': _subtitleCtrl.text,
      'cta_text': _ctaCtrl.text,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('TITLE'),
        const SizedBox(height: 6),
        TextFormField(
          controller: _titleCtrl,
          onChanged: (_) => _notify(),
          decoration:
              const InputDecoration(hintText: 'Special Promotion'),
        ),
        const SizedBox(height: 14),
        _label('SUBTITLE'),
        const SizedBox(height: 6),
        TextFormField(
          controller: _subtitleCtrl,
          onChanged: (_) => _notify(),
          decoration: const InputDecoration(
              hintText: 'Limited time offer — book now.'),
        ),
        const SizedBox(height: 14),
        _label('BUTTON LABEL'),
        const SizedBox(height: 6),
        TextFormField(
          controller: _ctaCtrl,
          onChanged: (_) => _notify(),
          decoration: const InputDecoration(hintText: 'Learn More'),
        ),
        const SizedBox(height: 20),
        _CmsMediaPicker(
          label: 'BACKGROUND IMAGE',
          value: widget.config['image_url'] as String? ?? '',
          onChanged: (v) =>
              widget.onChanged({...widget.config, 'image_url': v}),
        ),
      ],
    );
  }
}

// ── FAQ config ────────────────────────────────────────────────────────────────

class _FaqConfig extends StatefulWidget {
  const _FaqConfig({required this.config, required this.onChanged});
  final Map<String, dynamic> config;
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  State<_FaqConfig> createState() => _FaqConfigState();
}

class _FaqConfigState extends State<_FaqConfig> {
  late final TextEditingController _titleCtrl;
  late List<Map<String, dynamic>> _items;

  @override
  void initState() {
    super.initState();
    _titleCtrl =
        TextEditingController(text: widget.config['title'] as String? ?? '');
    _items = ((widget.config['items'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  void _notify() {
    widget.onChanged({
      ...widget.config,
      'title': _titleCtrl.text,
      'items': _items,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('TITLE'),
        const SizedBox(height: 6),
        TextFormField(
          controller: _titleCtrl,
          onChanged: (_) => _notify(),
          decoration: const InputDecoration(
              hintText: 'Frequently Asked Questions'),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            _label('Q&A ITEMS'),
            const Spacer(),
            TextButton.icon(
              onPressed: () {
                setState(
                    () => _items.add({'question': '', 'answer': ''}));
                _notify();
              },
              icon: const Icon(Icons.add_rounded, size: 14),
              label: const Text('Add Q&A'),
              style: TextButton.styleFrom(
                  textStyle: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._items.asMap().entries.map((entry) {
          final i = entry.key;
          return _FaqItemRow(
            key: ValueKey('faq-$i'),
            item: entry.value,
            onChanged: (updated) {
              setState(() => _items[i] = updated);
              _notify();
            },
            onDelete: () {
              setState(() => _items.removeAt(i));
              _notify();
            },
          );
        }),
      ],
    );
  }
}

class _FaqItemRow extends StatefulWidget {
  const _FaqItemRow({
    super.key,
    required this.item,
    required this.onChanged,
    required this.onDelete,
  });
  final Map<String, dynamic> item;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final VoidCallback onDelete;

  @override
  State<_FaqItemRow> createState() => _FaqItemRowState();
}

class _FaqItemRowState extends State<_FaqItemRow> {
  late final TextEditingController _qCtrl;
  late final TextEditingController _aCtrl;

  @override
  void initState() {
    super.initState();
    _qCtrl =
        TextEditingController(text: widget.item['question'] as String? ?? '');
    _aCtrl =
        TextEditingController(text: widget.item['answer'] as String? ?? '');
  }

  @override
  void dispose() {
    _qCtrl.dispose();
    _aCtrl.dispose();
    super.dispose();
  }

  void _notify() {
    widget.onChanged({'question': _qCtrl.text, 'answer': _aCtrl.text});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _qCtrl,
                  onChanged: (_) => _notify(),
                  decoration: const InputDecoration(
                    labelText: 'Question',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: widget.onDelete,
                icon: const Icon(Icons.delete_outline_rounded,
                    size: 16, color: AppColors.error),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _aCtrl,
            maxLines: 3,
            onChanged: (_) => _notify(),
            decoration: const InputDecoration(
              labelText: 'Answer',
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }
}

// ── CTA config ────────────────────────────────────────────────────────────────

class _CtaConfig extends StatefulWidget {
  const _CtaConfig({required this.config, required this.onChanged});
  final Map<String, dynamic> config;
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  State<_CtaConfig> createState() => _CtaConfigState();
}

class _CtaConfigState extends State<_CtaConfig> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _subtitleCtrl;
  late final TextEditingController _btnCtrl;
  late final TextEditingController _urlCtrl;

  @override
  void initState() {
    super.initState();
    _titleCtrl =
        TextEditingController(text: widget.config['title'] as String? ?? '');
    _subtitleCtrl = TextEditingController(
        text: widget.config['subtitle'] as String? ?? '');
    _btnCtrl = TextEditingController(
        text: widget.config['button_text'] as String? ?? 'Book Now');
    _urlCtrl = TextEditingController(
        text: widget.config['button_url'] as String? ?? '/');
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
    _btnCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  void _notify() {
    widget.onChanged({
      ...widget.config,
      'title': _titleCtrl.text,
      'subtitle': _subtitleCtrl.text,
      'button_text': _btnCtrl.text,
      'button_url': _urlCtrl.text,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('HEADING'),
        const SizedBox(height: 6),
        TextFormField(
          controller: _titleCtrl,
          onChanged: (_) => _notify(),
          decoration:
              const InputDecoration(hintText: 'Ready to Get Started?'),
        ),
        const SizedBox(height: 14),
        _label('SUB-HEADING'),
        const SizedBox(height: 6),
        TextFormField(
          controller: _subtitleCtrl,
          onChanged: (_) => _notify(),
          decoration: const InputDecoration(
              hintText: 'Book your first service today.'),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('BUTTON TEXT'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _btnCtrl,
                    onChanged: (_) => _notify(),
                    decoration:
                        const InputDecoration(hintText: 'Book Now'),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('BUTTON URL'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _urlCtrl,
                    onChanged: (_) => _notify(),
                    decoration:
                        const InputDecoration(hintText: '/categories'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
