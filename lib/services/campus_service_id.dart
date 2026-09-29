/// Stable service identity used by CampusSession request boundaries.
///
/// This value identifies a campus service, not a credential representation.
class CampusServiceId {
  final String value;

  const CampusServiceId(this.value);

  @override
  bool operator ==(Object other) =>
      other is CampusServiceId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

class CampusServices {
  const CampusServices._();

  static const unifiedIdentity = CampusServiceId('unified-identity');
  static const informationPortal = CampusServiceId('information-portal');
  static const courseOnline = CampusServiceId('course-online');
  static const tronclassMobile = CampusServiceId('tronclass-mobile');
  static const classroomRecording = CampusServiceId('classroom-recording');
  static const sportsPortal = CampusServiceId('sports-portal');
  static const academicAffairs = CampusServiceId('academic-affairs');
  static const graduateAcademicAffairs = CampusServiceId(
    'graduate-academic-affairs',
  );
  static const campusApp = CampusServiceId('campus-app');
  static const roomReservation = CampusServiceId('room-reservation');
  static const libraryOpac = CampusServiceId('library-opac');
  static const qualityAssurance = CampusServiceId('quality-assurance');
  static const mobileCampus = CampusServiceId('mobile-campus');
  static const commuterBus = CampusServiceId('commuter-bus');
  static const networkSelfService = CampusServiceId('network-self-service');

  static const all = <CampusServiceId>[
    unifiedIdentity,
    informationPortal,
    courseOnline,
    tronclassMobile,
    classroomRecording,
    sportsPortal,
    academicAffairs,
    graduateAcademicAffairs,
    campusApp,
    roomReservation,
    libraryOpac,
    qualityAssurance,
    mobileCampus,
    commuterBus,
    networkSelfService,
  ];
}
