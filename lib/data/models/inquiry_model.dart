import 'package:cloud_firestore/cloud_firestore.dart';

enum InquiryStatus { pending, answered }

InquiryStatus _statusFromString(String? raw) => switch (raw) {
  'answered' => InquiryStatus.answered,
  _ => InquiryStatus.pending,
};

/// 사용자가 보낸 1:1 문의 한 건. 답변은 `inquiries/{id}/replies` 서브컬렉션에
/// 별도로 쌓인다(문의 원문은 사용자가 나중에 고칠 수 없게 하기 위함 —
/// firestore.rules에서 update를 관리자만 허용).
class InquiryModel {
  final String id;
  final String userId;
  final String userEmail;
  final String subject;
  final String message;
  final InquiryStatus status;
  final DateTime createdAt;

  const InquiryModel({
    required this.id,
    required this.userId,
    required this.userEmail,
    required this.subject,
    required this.message,
    required this.status,
    required this.createdAt,
  });

  factory InquiryModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const {};
    return InquiryModel(
      id: doc.id,
      userId: (data['userId'] as String?) ?? '',
      userEmail: (data['userEmail'] as String?) ?? '',
      subject: (data['subject'] as String?) ?? '',
      message: (data['message'] as String?) ?? '',
      status: _statusFromString(data['status'] as String?),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toCreatePayload() => {
    'userId': userId,
    'userEmail': userEmail,
    'subject': subject,
    'message': message,
    'status': 'pending',
    'createdAt': FieldValue.serverTimestamp(),
  };
}

/// 문의 스레드의 답변(사용자가 보낸 추가 메시지 포함) 한 건.
class InquiryReplyModel {
  final String id;
  final String from; // 'admin' | 'user'
  final String message;
  final DateTime createdAt;

  const InquiryReplyModel({
    required this.id,
    required this.from,
    required this.message,
    required this.createdAt,
  });

  bool get isFromAdmin => from == 'admin';

  factory InquiryReplyModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const {};
    return InquiryReplyModel(
      id: doc.id,
      from: (data['from'] as String?) ?? 'user',
      message: (data['message'] as String?) ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
