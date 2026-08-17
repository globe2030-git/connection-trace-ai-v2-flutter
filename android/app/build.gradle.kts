import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 릴리스 서명 정보는 저장소 밖(android/key.properties, .gitignore 처리됨)에서
// 읽는다. 파일이 없으면(예: CI, 다른 개발자 기기) 릴리스 서명 설정을 건너뛰고
// 아래 buildTypes에서 debug 키로 폴백한다 — 빌드 자체가 깨지지 않게 하기 위함.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.connectiontrace.connection_trace_ai_flutter"
    // geocoding_android(androidx.exifinterface/annotation-experimental)가 API 34+
    // 컴파일을 요구해서 Flutter 기본값(33)보다 올려야 함.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // call_log 패키지가 core library desugaring을 요구함(Java 8+ API를
        // 오래된 Android API 레벨에서도 쓸 수 있게 변환해주는 기능).
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.connectiontrace.connection_trace_ai_flutter"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

    }

    packaging {
        jniLibs {
            // ⚠️ **x86_64(에뮬레이터용) 네이티브를 APK에서 뺀다**
            // (2026-08-17 사용자 결정).
            //
            // OpenCV가 들어오면서 ABI마다 네이티브가 붙는다. 스토어는 기기에
            // 맞는 ABI 하나만 내려보내므로 **실사용자 용량과는 무관**하지만,
            // **테스터 배포는 APK를 통째로 보내서** 그대로 걸린다 —
            // 지금이 테스터 배포 단계다.
            //
            // ⚠️ **`defaultConfig { ndk { abiFilters } }`로는 안 됐다**
            // (2026-08-17 실측 — 넣고 빌드했더니 x86_64가 그대로였다).
            // Flutter의 gradle 플러그인이 그 설정을 덮는 것으로 보인다.
            // 그래서 **포장 단계에서 뺀다.**
            //
            // 짝으로 `tool/build_app.sh`의 `--target-platform`도 있어야 한다 —
            // 그쪽은 Flutter·Dart가 만드는 .so를, 여기는 **외부 패키지 AAR이
            // 넣는 .so**(ML Kit 11.6MB 등)를 맡는다.
            //
            // 잃는 것: **에뮬레이터에서 앱을 못 돌린다.** ⚠️ 다만 이 저장소는
            // ML Kit이 arm64 시뮬레이터를 지원하지 않아 **이미 에뮬레이터에서
            // OCR을 못 돌린다** — 잃는 범위가 그만큼이다.
            excludes += setOf("lib/x86_64/**", "lib/x86/**")
        }
    }

    signingConfigs {
        // key.properties가 있을 때만 업로드 키 서명 설정을 만든다.
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // key.properties가 있으면 업로드 키로 서명, 없으면 debug 키로 폴백
            // (`flutter run --release`가 서명 파일 없는 환경에서도 동작하도록).
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// google_mlkit_text_recognition은 한글/중국어/일본어/데바나가리 스크립트 모델을
// compileOnly로만 선언해서(APK 용량 절약을 위해 앱이 opt-in하도록 설계됨), 실제
// 기기에서 TextRecognitionScript.korean으로 인식기를 만들면
// NoClassDefFoundError(KoreanTextRecognizerOptions$Builder)로 즉시 크래시했다.
// 명함에 한글이 들어가는 게 기본 시나리오라 한국어 모델을 명시적으로 포함시킨다.
dependencies {
    implementation("com.google.mlkit:text-recognition-korean:16.0.1")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
