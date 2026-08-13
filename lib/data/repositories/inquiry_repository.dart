import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/inquiry_model.dart';

class InquiryRepository {
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// 로그인한 본인이 보낸 문의만 최신순으로 구독한다(firestore.rules가
  /// userId == 본인 uid인 문서만 읽도록 강제하므로, 다른 조건 없이도
  /// where(userId)만으로 본인 것만 정확히 필터링된다).
  Stream<List<InquiryModel>> watchMyInquiries(String uid) {
    return _db
        .collection('inquiries')
        .where('userId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(InquiryModel.fromFirestore).toList());
  }

  Stream<List<InquiryReplyModel>> watchReplies(String inquiryId) {
    return _db
        .collection('inquiries')
        .doc(inquiryId)
        .collection('replies')
        .orderBy('createdAt')
        .snapshots()
        .map(
          (snap) => snap.docs.map(InquiryReplyModel.fromFirestore).toList(),
        );
  }

  Future<void> submitInquiry({
    required String userId,
    String userName = '',
    required String userEmail,
    required String subject,
    required String message,
  }) {
    final model = InquiryModel(
      id: '',
      userId: userId,
      userName: userName,
      userEmail: userEmail,
      subject: subject,
      message: message,
      status: InquiryStatus.pending,
      createdAt: DateTime.now(),
    );
    return _db.collection('inquiries').add(model.toCreatePayload());
  }

  /// 문의에 사용자가 추가 메시지를 보낸다(예: 답변에 대한 재질문). 관리자가
  /// 보는 목록에서 "미답변"으로 다시 보이게 status도 되돌린다 — 이건
  /// 규칙상 관리자만 update할 수 있으므로 실제로는 Cloud Functions가
  /// 배포된 뒤(task #44 참고) 트리거로 처리하거나, 그 전까지는 관리자가
  /// 콘솔에서 수동으로 상태를 되돌려야 한다.
  Future<void> addUserReply({
    required String inquiryId,
    required String message,
  }) {
    return _db
        .collection('inquiries')
        .doc(inquiryId)
        .collection('replies')
        .add({
          'from': 'user',
          'message': message,
          'createdAt': FieldValue.serverTimestamp(),
        });
  }
}
