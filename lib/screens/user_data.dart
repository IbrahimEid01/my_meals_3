class UserData {
  String? userName;
  int? userAge;
  double? userHeight;
  double? userWeight;
  String? userCondition;

  UserData({
    this.userName,
    this.userAge,
    this.userHeight,
    this.userWeight,
    this.userCondition,
  });
  // تحويل بيانات المستخدم إلى JSON
  Map<String, dynamic> toJson() {
    return {
      'userName': userName,
      'userAge': userAge,
      'userHeight': userHeight,
      'userWeight': userWeight,
      'userCondition': userCondition,
    };
  }

  // تحويل JSON إلى بيانات المستخدم
  factory UserData.fromJson(Map<String, dynamic> json) {
    return UserData(
      userName: json['userName'],
      userAge: json['userAge'],
      userHeight: json['userHeight'],
      userWeight: json['userWeight'],
      userCondition: json['userCondition'],
    );
  }
}