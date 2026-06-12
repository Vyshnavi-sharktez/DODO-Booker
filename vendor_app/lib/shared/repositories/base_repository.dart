import 'package:supabase_flutter/supabase_flutter.dart';

abstract class BaseRepository {
  const BaseRepository(this.supabase);

  final SupabaseClient supabase;
}
