# google_mlkit_text_recognition은 스크립트별(중국어/힌디/일본어 등) 인식기를
# compileOnly로 선언해 앱이 opt-in한 것만 포함하게 설계돼 있다(APK 용량 절약).
# 우리 앱은 한국어/영어만 명시적으로 포함시켰기 때문에(build.gradle.kts 참고)
# 나머지 스크립트 클래스는 실제로 APK에 없는 게 의도된 상태 — R8이 이를
# "누락된 클래스"로 보고 릴리스 빌드를 실패시키는 걸 막기 위해 경고를 끈다.
# (AGP가 build/app/outputs/mapping/release/missing_rules.txt에 자동 생성해 준 규칙)
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
