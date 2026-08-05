import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/notice_model.dart';

/// 공지사항 조회 전용 — 작성/수정은 관리자 콘솔(웹)에서만 하므로 앱 쪽은
/// 읽기 스트림만 제공한다.
class NoticeRepository {
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  Stream<List<NoticeModel>> watchPublishedNotices() {
    return _db
        .collection('notices')
        .where('published', isEqualTo: true)
        .orderBy('pinned', descending: true)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(NoticeModel.fromFirestore).toList());
  }
}
