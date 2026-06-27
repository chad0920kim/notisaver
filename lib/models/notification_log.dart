class NotificationLog {
  final int? id;
  final String packageName;
  final String title;
  final String content;
  final int timestamp;

  NotificationLog({
    this.id,
    required this.packageName,
    required this.title,
    required this.content,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'package_name': packageName,
      'title': title,
      'content': content,
      'timestamp': timestamp,
    };
    if (id != null) {
      map['id'] = id;
    }
    return map;
  }

  factory NotificationLog.fromMap(Map<String, dynamic> map) {
    return NotificationLog(
      id: map['id'] as int?,
      packageName: map['package_name'] as String? ?? '',
      title: map['title'] as String? ?? '',
      content: map['content'] as String? ?? '',
      timestamp: map['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(timestamp);
}
