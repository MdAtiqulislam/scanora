class PassportData {
  final String? documentType;
  final String? issuingCountry;
  final String? surname;
  final String? givenNames;
  final String? passportNumber;
  final String? nationality;
  final DateTime? dateOfBirth;
  final String? sex;
  final DateTime? expiryDate;
  final bool isValid;
  final String? rawMrz;

  const PassportData({
    this.documentType,
    this.issuingCountry,
    this.surname,
    this.givenNames,
    this.passportNumber,
    this.nationality,
    this.dateOfBirth,
    this.sex,
    this.expiryDate,
    this.isValid = true,
    this.rawMrz,
  });

  String get fullName => '${givenNames ?? ''} ${surname ?? ''}'.trim();

  Map<String, dynamic> toMap() {
    return {
      'documentType': documentType,
      'issuingCountry': issuingCountry,
      'surname': surname,
      'givenNames': givenNames,
      'passportNumber': passportNumber,
      'nationality': nationality,
      'dateOfBirth': dateOfBirth?.toIso8601String(),
      'sex': sex,
      'expiryDate': expiryDate?.toIso8601String(),
      'isValid': isValid,
      'rawMrz': rawMrz,
    };
  }
}
