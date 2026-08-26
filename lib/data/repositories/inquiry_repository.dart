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

  /// 관리자 목록의 기본 표시 건수. "더 보기"를 누르면 이만큼씩 늘어난다.
  static const int adminPageSize = 50;

  /// 관리자가 최신 문의부터 [limit]건을 구독한다(firestore.rules의 isAdmin()
  /// 권한 필요).
  ///
  /// ## ⚠️ 왜 상한이 있나 (추가 480)
  ///
  /// 예전에는 상한 없이 `inquiries` 컬렉션 전체를 구독했다. 그러면 **읽기
  /// 요금이 이용자 수가 아니라 누적 문의 수에 비례한다** — 관리자가 이
  /// 화면을 열 때마다 지금까지의 문의를 전부 내려받는다.
  ///
  /// 📌 **테스터 수에서는 안 드러난다.** 드러날 때는 이미 요금이 나간 뒤다.
  ///
  /// ## ⚠️ 상한이 검색 범위를 바꾼다 — 화면이 그걸 알려야 한다
  ///
  /// 이 화면의 검색·상태 필터는 **내려받은 목록 안에서** 도는 클라이언트
  /// 필터다. 즉 상한을 걸면 **검색도 그 범위 안에서만** 된다. 그래서
  /// `admin_inquiry_view.dart`가 "최근 N건에서 찾았다"를 문구로 밝히고
  /// "더 보기"로 범위를 넓힐 수 있게 해 두었다. **상한만 걸고 화면을 그대로
  /// 두면 오래된 문의가 조용히 안 보이게 된다.**
  Stream<List<InquiryModel>> watchAllInquiriesForAdmin({
    int limit = adminPageSize,
  }) {
    return _db
        .collection('inquiries')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(InquiryModel.fromFirestore).toList());
  }

  /// 관리자가 사용자 문의에 답변을 등록하고 상태를 '답변완료(answered)'로 업데이트한다.
  Future<void> addAdminReply({
    required String inquiryId,
    required String message,
  }) async {
    final batch = _db.batch();
    final inquiryRef = _db.collection('inquiries').doc(inquiryId);
    final replyRef = inquiryRef.collection('replies').doc();

    batch.set(replyRef, {
      'from': 'admin',
      'message': message,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(inquiryRef, {
      'status': 'answered',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  // 사용자의 AI 사용량 조회는 여기 두지 않는다. `users/{uid}` 문서는
  // `firestore.rules`에서 본인만 읽을 수 있고(같은 문서에 명함 복호화 키가
  // 들어 있어 관리자에게 열면 안 된다), 서버에 이미 관리자 전용
  // `getUserUsage` 함수가 있다 — `AiUsageService.fetchForAdmin`을 쓴다.
  // 예전에 여기서 Firestore를 직접 읽던 구현은 항상 권한 거부가 났고,
  // 그 실패를 삼켜 0을 그렸다(backlog 추가 178).
}
