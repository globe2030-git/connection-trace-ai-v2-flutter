// 웹이 아닌 플랫폼(Android/iOS/데스크톱)에서는 아무 것도 하지 않는 더미 구현.
// web_tab_guard.dart의 conditional export가 dart:html 사용 불가 환경에서 이 파일을 대신 쓴다.
class WebTabGuard {
  static void install({required void Function(bool shiftKey) onTab}) {}
  static void uninstall() {}
}
