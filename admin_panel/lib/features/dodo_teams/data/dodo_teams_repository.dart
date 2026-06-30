import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models/dodo_team.dart';

class DodoTeamsRepository {
  final SupabaseClient _supabase;
  const DodoTeamsRepository(this._supabase);

  Future<List<DodoTeam>> fetchDodoTeams() async {
    final data = await _supabase
        .from('dodo_teams')
        .select()
        .order('created_at', ascending: false);
    return (data as List<dynamic>)
        .map((r) => DodoTeam.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<DodoTeam> createDodoTeam({
    required String teamName,
    String? supervisorName,
    String? phone,
    String? email,
    String? locality,
    required int membersCount,
    required String status,
  }) async {
    final data = await _supabase
        .from('dodo_teams')
        .insert({
          'team_name': teamName,
          'supervisor_name':
              supervisorName?.isNotEmpty == true ? supervisorName : null,
          'phone': phone?.isNotEmpty == true ? phone : null,
          'email': email?.isNotEmpty == true ? email : null,
          'locality': locality?.isNotEmpty == true ? locality : null,
          'members_count': membersCount,
          'active_jobs': 0,
          'status': status,
          'is_active': status != 'Inactive',
        })
        .select()
        .single();
    return DodoTeam.fromMap(data);
  }

  Future<DodoTeam> updateDodoTeam(
    String id, {
    required String teamName,
    String? supervisorName,
    String? phone,
    String? email,
    String? locality,
    required int membersCount,
    required String status,
  }) async {
    final data = await _supabase
        .from('dodo_teams')
        .update({
          'team_name': teamName,
          'supervisor_name':
              supervisorName?.isNotEmpty == true ? supervisorName : null,
          'phone': phone?.isNotEmpty == true ? phone : null,
          'email': email?.isNotEmpty == true ? email : null,
          'locality': locality?.isNotEmpty == true ? locality : null,
          'members_count': membersCount,
          'status': status,
          'is_active': status != 'Inactive',
        })
        .eq('id', id)
        .select()
        .single();
    return DodoTeam.fromMap(data);
  }

  Future<void> deleteDodoTeam(String id) async {
    await _supabase.from('dodo_teams').delete().eq('id', id);
  }
}
