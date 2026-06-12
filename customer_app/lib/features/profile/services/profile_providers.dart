import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'profile_service.dart';
import '../../../models/profile_model.dart';

final profileServiceProvider = Provider<ProfileService>(
  (ref) => ProfileService(),
);

final profileProvider = FutureProvider<ProfileModel>(
  (ref) => ref.read(profileServiceProvider).fetchProfile(),
);
