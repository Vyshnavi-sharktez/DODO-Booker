import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/cms_page.dart';
import '../domain/models/seo_setting.dart';

class CmsRepository {
  final SupabaseClient _supabase;

  const CmsRepository(this._supabase);

  // ── CMS Pages ──────────────────────────────────────────────────────────────

  Future<List<CmsPage>> fetchPages() async {
    final data = await _supabase
        .from('cms_pages')
        .select()
        .order('created_at', ascending: false);
    return (data as List<dynamic>)
        .map((r) => CmsPage.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<CmsPage> createPage({
    required String pageSlug,
    required String pageTitle,
    String? pageContent,
    required bool isPublished,
  }) async {
    final data = await _supabase
        .from('cms_pages')
        .insert({
          'page_slug': pageSlug,
          'page_title': pageTitle,
          'page_content': pageContent,
          'is_published': isPublished,
        })
        .select()
        .single();
    return CmsPage.fromMap(data);
  }

  Future<CmsPage> updatePage(
    String id, {
    required String pageSlug,
    required String pageTitle,
    String? pageContent,
    required bool isPublished,
  }) async {
    final data = await _supabase
        .from('cms_pages')
        .update({
          'page_slug': pageSlug,
          'page_title': pageTitle,
          'page_content': pageContent,
          'is_published': isPublished,
        })
        .eq('id', id)
        .select()
        .single();
    return CmsPage.fromMap(data);
  }

  Future<void> deletePage(String id) async {
    await _supabase.from('cms_pages').delete().eq('id', id);
  }

  Future<void> updatePublished(String id, {required bool isPublished}) async {
    await _supabase
        .from('cms_pages')
        .update({'is_published': isPublished})
        .eq('id', id);
  }

  // ── SEO Settings ───────────────────────────────────────────────────────────

  Future<SeoSetting?> fetchSeoForSlug(String slug) async {
    final data = await _supabase
        .from('seo_settings')
        .select()
        .eq('page_slug', slug)
        .maybeSingle();
    if (data == null) return null;
    return SeoSetting.fromMap(data);
  }

  Future<SeoSetting> upsertSeo({
    required String pageSlug,
    String? metaTitle,
    String? metaDescription,
    String? metaKeywords,
    String? ogImageUrl,
    String? canonicalUrl,
  }) async {
    final data = await _supabase
        .from('seo_settings')
        .upsert(
          {
            'page_slug': pageSlug,
            'meta_title': metaTitle?.isEmpty == true ? null : metaTitle,
            'meta_description':
                metaDescription?.isEmpty == true ? null : metaDescription,
            'meta_keywords':
                metaKeywords?.isEmpty == true ? null : metaKeywords,
            'og_image_url': ogImageUrl?.isEmpty == true ? null : ogImageUrl,
            'canonical_url': canonicalUrl?.isEmpty == true ? null : canonicalUrl,
          },
          onConflict: 'page_slug',
        )
        .select()
        .single();
    return SeoSetting.fromMap(data);
  }
}
