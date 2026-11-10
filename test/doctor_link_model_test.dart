import 'package:flutter_test/flutter_test.dart';
import 'package:medication_follow_up_app/models/doctor_link.dart';

class _FakeTimestamp {
  _FakeTimestamp(this._value);
  final DateTime _value;
  DateTime toDate() => _value;
}

void main() {
  final consented = DateTime.utc(2026, 11, 1, 9);

  test('DoctorLink round-trips and omits server timestamps', () {
    const link = DoctorLink(
      id: 'p1_d1',
      patientId: 'p1',
      doctorId: 'd1',
      linkCode: 'ABCDEFGH23',
      status: LinkStatus.active,
      patientName: 'Test Patient',
      doctorName: 'Test Doctor',
    );

    final map = link.toConsentFields();
    expect(map.keys, isNot(contains('consentedAt')));
    expect(DoctorLink.consentServerTimeFields, ['consentedAt']);
    expect(map['status'], 'active');

    final restored = DoctorLink.fromMap('p1_d1', {
      ...map,
      'consentedAt': _FakeTimestamp(consented),
    });
    expect(restored.patientId, 'p1');
    expect(restored.doctorName, 'Test Doctor');
    expect(restored.consentedAt, consented);
    expect(restored.isActive, isTrue);
  });

  test('revoked link reads revocation fields', () {
    final link = DoctorLink.fromMap('p1_d1', {
      'patientId': 'p1',
      'doctorId': 'd1',
      'linkCode': 'ABCDEFGH23',
      'status': 'revoked',
      'revokedAt': consented,
      'revokedBy': 'd1',
    });
    expect(link.isActive, isFalse);
    expect(link.revokedBy, 'd1');
    expect(link.revokedAt, consented);
  });

  test('DoctorCode expires 30 days after creation', () {
    final code = DoctorCode.fromMap('ABCDEFGH23', {
      'doctorId': 'd1',
      'doctorName': 'Test Doctor',
      'active': true,
      'createdAt': _FakeTimestamp(consented),
    });
    expect(code.expiresAt, consented.add(const Duration(days: 30)));
    expect(code.isUsableAt(consented.add(const Duration(days: 29))), isTrue);
    expect(code.isUsableAt(consented.add(const Duration(days: 30))), isFalse);
    expect(code.toCreateFields().keys, isNot(contains('createdAt')));
    expect(DoctorCode.createServerTimeFields, ['createdAt']);
  });

  test('revocation payload and unsupported timestamp types', () {
    expect(DoctorLink.revocationFields('d1'), {
      'status': 'revoked',
      'revokedBy': 'd1',
    });
    expect(DoctorLink.revocationServerTimeFields, ['revokedAt']);
    expect(
      () => DoctorLink.fromMap('p1_d1', {
        'patientId': 'p1',
        'doctorId': 'd1',
        'linkCode': 'ABCDEFGH23',
        'status': 'active',
        'consentedAt': '2026-11-01',
      }),
      throwsFormatException,
    );
  });

  test('code format: canonical storage, display grouping, 50-bit space', () {
    expect(doctorLinkId('p1', 'd1'), 'p1_d1');
    expect(doctorCodeAlphabet.length, 32); // 5 bits x 10 chars = 50 bits
    expect(doctorCodeAlphabet, isNot(matches(RegExp('[IO01]'))));
    expect(normalizeDoctorCode(' abcd-efgh-23 '), 'ABCDEFGH23');
    expect(isValidDoctorCode('ABCDEFGH23'), isTrue);
    expect(isValidDoctorCode('ABCD-EFGH-23'), isFalse);
    expect(isValidDoctorCode('ABCDEFGHI1'), isFalse);
    expect(isValidDoctorCode('ABCDEFGH2'), isFalse);
    expect(formatDoctorCodeForDisplay('ABCDEFGH23'), 'ABCD-EFGH-23');
  });
}
