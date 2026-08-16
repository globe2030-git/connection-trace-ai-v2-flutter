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
    // 명함 테두리 검출(B′). 안드로이드에는 아이폰의 Vision 같은 OS 기본
    // 검출이 없어 OpenCV로 직접 찾는다.
    //
    // ⚠️ **미리 빌드된 것을 받아 쓴다.** Dart에서 바로 부르는 `dartcv4`도
    // 되긴 하지만(실측 확인), 그쪽은 **OpenCV 소스를 우리 기계에서 컴파일**
    // 하는데 그 과정이 경로를 따옴표 없이 셸에 넘긴다. 저장소가 있는 볼륨
    // 이름이 `X31(VM)` — **괄호가 들어 있어** 빌드가 깨진다:
    //
    //     /bin/sh: syntax error near unexpected token `('
    //
    // 기성품은 컴파일 단계가 없어 그 문제가 아예 생기지 않는다.
    // 자세한 경위는 `CardRectDetectorPlugin.kt` 머리말과 backlog 추가 273.
    //
    // 용량 실측(2026-08-16): `dartcv4`는 arm64 네이티브 +10.5MB였다.
    // 이쪽 증분은 붙인 뒤 다시 잰다.
    implementation("org.opencv:opencv:4.14.0")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
