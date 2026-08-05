import 'package:cloud_firestore/cloud_firestore.dart';

/// 공지사항 한 건. 관리자 콘솔(Firestore `notices` 컬렉션)에서 작성하고,
/// 앱은 `published == true`인 것만 읽는다(firestore.rules 참고).
class NoticeModel {
  final String id;
  final String title;
  final String bodyMarkdown;
  final bool pinned;
  final bool published;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const NoticeModel({
    required this.id,
    required this.title,
    required this.bodyMarkdown,
    required this.pinned,
    required this.published,
    required this.createdAt,
    this.updatedAt,
  });

  factory NoticeModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return NoticeModel(
      id: doc.id,
      title: (data['title'] as String?) ?? '',
      bodyMarkdown: (data['bodyMarkdown'] as String?) ?? '',
      pinned: (data['pinned'] as bool?) ?? false,
      published: (data['published'] as bool?) ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}
