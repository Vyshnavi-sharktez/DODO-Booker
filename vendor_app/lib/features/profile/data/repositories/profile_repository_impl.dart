import '../../domain/models/vendor_profile.dart';
import '../../domain/repositories/i_profile_repository.dart';
import '../datasources/profile_remote_datasource.dart';

class ProfileRepositoryImpl implements IProfileRepository {
  const ProfileRepositoryImpl(this._datasource);
  final ProfileRemoteDatasource _datasource;

  @override
  Future<VendorProfile?> getProfileByPhone(String phone) async {
    final row = await _datasource.fetchByPhone(phone);
    if (row == null) return null;
    return VendorProfile.fromMap(row);
  }

  @override
  Future<void> updateProfileByPhone({
    required String phone,
    required Map<String, dynamic> fields,
  }) =>
      _datasource.updateByPhone(phone: phone, fields: fields);
}
