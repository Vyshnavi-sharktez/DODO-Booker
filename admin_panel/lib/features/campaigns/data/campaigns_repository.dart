import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/campaign.dart';

class CampaignsRepository {
  final SupabaseClient _supabase;
  const CampaignsRepository(this._supabase);

  Future<List<Campaign>> fetchCampaigns() async {
    final data = await _supabase
        .from('campaigns')
        .select()
        .order('created_at', ascending: false);
    return (data as List<dynamic>)
        .map((r) => Campaign.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// Returns recipient count and up to 5 masked phone samples.
  /// Never returns actual phone numbers.
  Future<({int count, List<String> sampleMasked})> getRecipientCount({
    required String channel,
    required String targetingType,
    String? targetingValue,
  }) async {
    final data = await _supabase.rpc(
      'get_campaign_recipient_count',
      params: {
        'p_channel': channel,
        'p_targeting_type': targetingType,
        if (targetingValue != null) 'p_targeting_value': targetingValue,
      },
    );
    final row = (data as List<dynamic>).first as Map<String, dynamic>;
    final samples = (row['sample_masked'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList() ??
        [];
    return (
      count: row['recipient_count'] as int? ?? 0,
      sampleMasked: samples,
    );
  }

  /// Creates a draft campaign and returns its UUID.
  Future<String> createCampaign({
    required String name,
    required String channel,
    required String message,
    required String templateId,
    required String templateLanguage,
    required String targetingType,
    String? targetingValue,
    String? targetingLabel,
    required bool isTestMode,
    int? estimatedCount,
  }) async {
    final id = await _supabase.rpc('create_campaign', params: {
      'p_name': name,
      'p_channel': channel,
      'p_message': message,
      'p_template_id': templateId,
      'p_template_language': templateLanguage,
      'p_targeting_type': targetingType,
      'p_targeting_value': targetingValue,
      'p_targeting_label': targetingLabel,
      'p_is_test_mode': isTestMode,
      'p_estimated_count': estimatedCount,
    });
    return id as String;
  }

  /// Invokes the send-sms-campaign Edge Function for SMS campaigns.
  Future<Map<String, dynamic>> sendSmsCampaign(String campaignId) async {
    final res = await _supabase.functions.invoke(
      'send-sms-campaign',
      body: {'campaign_id': campaignId},
    );
    if (res.data == null) {
      throw Exception('No response from send-sms-campaign function');
    }
    final data = res.data as Map<String, dynamic>;
    if (data['error'] != null) {
      throw Exception(data['error'] as String);
    }
    return data;
  }

  /// Resets a failed campaign back to draft for retry.
  Future<void> resetTodrft(String campaignId) async {
    await _supabase.rpc(
      'reset_campaign_to_draft',
      params: {'p_campaign_id': campaignId},
    );
  }

  Future<void> deleteCampaign(String campaignId) async {
    await _supabase.from('campaigns').delete().eq('id', campaignId);
  }

  /// Reuses existing broadcast_notifications targeting options.
  Future<List<({String value, String label})>> getTargetingOptions({
    required String targetingType,
  }) async {
    final data = await _supabase.rpc(
      'get_broadcast_targeting_options',
      params: {
        'p_targeting_type': targetingType,
        'p_audience': 'customers',
      },
    );
    return (data as List<dynamic>).map((row) {
      final r = row as Map<String, dynamic>;
      return (value: r['value'] as String, label: r['label'] as String);
    }).toList();
  }
}
