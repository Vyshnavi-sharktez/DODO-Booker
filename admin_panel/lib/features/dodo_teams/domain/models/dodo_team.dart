class DodoTeam {
  final String id;
  final String teamName;
  final String? supervisorName;
  final String? phone;
  final String? email;
  final String? locality;
  final int membersCount;
  final int activeJobs;
  final String status; // 'Available', 'Busy', 'Inactive'
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const DodoTeam({
    required this.id,
    required this.teamName,
    this.supervisorName,
    this.phone,
    this.email,
    this.locality,
    this.membersCount = 0,
    this.activeJobs = 0,
    this.status = 'Available',
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  factory DodoTeam.fromMap(Map<String, dynamic> map) {
    return DodoTeam(
      id: map['id'] as String,
      teamName: map['team_name'] as String? ?? '',
      supervisorName: map['supervisor_name'] as String?,
      phone: map['phone'] as String?,
      email: map['email'] as String?,
      locality: map['locality'] as String?,
      membersCount: map['members_count'] as int? ?? 0,
      activeJobs: map['active_jobs'] as int? ?? 0,
      status: map['status'] as String? ?? 'Available',
      isActive: map['is_active'] as bool? ?? true,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String)
          : null,
    );
  }

  DodoTeam copyWith({
    String? teamName,
    String? supervisorName,
    String? phone,
    String? email,
    String? locality,
    int? membersCount,
    int? activeJobs,
    String? status,
    bool? isActive,
  }) {
    return DodoTeam(
      id: id,
      teamName: teamName ?? this.teamName,
      supervisorName: supervisorName ?? this.supervisorName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      locality: locality ?? this.locality,
      membersCount: membersCount ?? this.membersCount,
      activeJobs: activeJobs ?? this.activeJobs,
      status: status ?? this.status,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
