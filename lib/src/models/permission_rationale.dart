/// Rationale dialog configuration for background location permission.
class PermissionRationale {
  final String title;
  final String message;
  final String positiveAction;
  final String negativeAction;

  const PermissionRationale({
    required this.title,
    required this.message,
    this.positiveAction = 'Allow',
    this.negativeAction = 'Deny',
  });

  factory PermissionRationale.fromMap(Map<String, dynamic> map) {
    return PermissionRationale(
      title: map['title'] as String? ?? '',
      message: map['message'] as String? ?? '',
      positiveAction: map['positiveAction'] as String? ?? 'Allow',
      negativeAction: map['negativeAction'] as String? ?? 'Deny',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'message': message,
      'positiveAction': positiveAction,
      'negativeAction': negativeAction,
    };
  }

  @override
  String toString() => 'PermissionRationale(title: $title)';
}
