plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
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

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
