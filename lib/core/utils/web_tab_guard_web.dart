import 'dart:async';
import 'dart:html' as html;

// [버그 수정] Flutter Web에서 Tab 키를 누르면 브라우저 자체의 기본 포커스 이동이
// Flutter의 Dart 레벨 포커스 처리보다 먼저 끼어들어 필드를 건너뛰는 현상이 반복
// 확인됐다. 그래서 document의 keydown을 capture 단계에서 직접 가로채
// preventDefault + stopImmediatePropagation으로 브라우저 기본 동작과 Flutter 엔진의
// 자체 키 처리 둘 다를 항상 원천 차단하고, 포커스 이동은 오직 우리 콜백 하나만
// 담당한다.
//
// 다만 한글처럼 조합형(IME) 입력 중(예: "이름"의 마지막 글자를 아직 조합 중일 때)
// Tab을 누르면 두 가지 문제가 있었다:
//   1. 조합이 끝나기 전에 곧바로 requestFocus()로 포커스를 옮기면(= 같은 콜스택
//      안에서 즉시 처리) TextInputClient의 조합 상태가 어긋나 Assertion 예외가
//      발생하고 포커스가 여러 칸씩 튀는 게 실측 확인됐다.
//   2. 반대로 조합 중일 땐 아예 관여하지 않고 넘겨버리면(이전 시도) 그 Tab 입력
//      "한 번"은 다시 브라우저 기본 동작에 넘어가버려서 정확히 그 첫 Tab에서만
//      필드를 건너뛰는 원래 버그가 되살아났다(이후 필드들은 조합 중이 아니어서
//      정상 동작).
// 그래서 이번엔 항상 우리가 제어권을 갖되(=매번 preventDefault), 조합 중이면
// compositionend(조합이 실제로 끝나는 시점)를 기다렸다가 포커스를 옮긴다.
// compositionend가 어떤 이유로든 안 오는 경우를 대비한 안전장치로 타임아웃도 둔다.
// 조합 중이 아닐 때도 같은 콜스택에서 즉시 처리하지 않고 한 틱 미뤄서, 브라우저
// 네이티브 keydown 이벤트 처리 도중 Dart 포커스 API를 재진입 호출하는 데서 오는
// 불안정성을 피한다.
class WebTabGuard {
  static void Function(html.Event)? _keyListener;
  static void Function(html.Event)? _compositionEndListener;
  static Timer? _fallbackTimer;

  static void install({required void Function(bool shiftKey) onTab}) {
    uninstall();

    void resolve(bool shiftKey) {
      _clearPendingCompositionWait();
      onTab(shiftKey);
    }

    void keyListener(html.Event event) {
      final e = event as html.KeyboardEvent;
      if (e.key != 'Tab') return;
      e.preventDefault();
      e.stopImmediatePropagation();

      final shiftKey = e.shiftKey;

      if (e.isComposing == true) {
        _clearPendingCompositionWait();
        void onCompositionEnd(html.Event _) => resolve(shiftKey);
        _compositionEndListener = onCompositionEnd;
        html.document.addEventListener('compositionend', onCompositionEnd);
        _fallbackTimer = Timer(const Duration(milliseconds: 200), () => resolve(shiftKey));
      } else {
        Timer(Duration.zero, () => resolve(shiftKey));
      }
    }

    _keyListener = keyListener;
    html.document.addEventListener('keydown', keyListener, true);
  }

  static void _clearPendingCompositionWait() {
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    final compositionEndListener = _compositionEndListener;
    if (compositionEndListener != null) {
      html.document.removeEventListener('compositionend', compositionEndListener);
      _compositionEndListener = null;
    }
  }

  static void uninstall() {
    _clearPendingCompositionWait();
    final listener = _keyListener;
    if (listener != null) {
      html.document.removeEventListener('keydown', listener, true);
      _keyListener = null;
    }
  }
}
