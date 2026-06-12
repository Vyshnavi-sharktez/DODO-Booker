import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/supabase_client_provider.dart';
import '../../core/services/local_storage_service.dart';

export '../../core/network/supabase_client_provider.dart'
    show supabaseClientProvider, authStateStreamProvider;

final localStorageProvider = FutureProvider<LocalStorageService>(
  (_) => LocalStorageService.create(),
);
