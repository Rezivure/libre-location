import '../enums/notification_priority.dart';

/// Configuration for the Android foreground service notification.
class NotificationConfig {
  final String? title;
  final String? text;
  final bool sticky;
  final NotificationPriority priority;

  const NotificationConfig({
    this.title,
    this.text,
    this.sticky = true,
    this.priority = NotificationPriority.defaultPriority,
  });

  factory NotificationConfig.fromMap(Map<String, dynamic> map) {
    return NotificationConfig(
      title: map['title'] as String?,
      text: map['text'] as String?,
      sticky: map['sticky'] as bool? ?? true,
      priority: NotificationPriority
          .values[map['priority'] as int? ?? NotificationPriority.defaultPriority.index],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (title != null) 'title': title,
      if (text != null) 'text': text,
      'sticky': sticky,
      'priority': priority.index,
    };
  }

  @override
  String toString() =>
      'NotificationConfig(title: $title, text: $text, sticky: $sticky, priority: ${priority.name})';
}
