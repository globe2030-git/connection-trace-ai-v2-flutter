allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// camera_android_camerax(camera 플러그인)가 의존하는 androidx.camera:camera-core 1.5.3의
// SurfaceRequest 클래스가 @org.jspecify.annotations.NonNull 타입 애노테이션으로
// androidx.concurrent.futures.CallbackToFutureAdapter를 참조하는데, 이 클래스가
// camera_android_camerax 모듈 자체의 의존성 그래프에는 전혀 없어서 "class file ...
// not found" 컴파일 에러가 났다. resolutionStrategy.force는 "이미 그래프에 있는"
// 의존성의 버전만 바꿀 뿐 없는 의존성을 추가해 주지는 않아서 효과가 없었고,
// :app 모듈에 추가해도 다른 서브프로젝트(플러그인) 모듈의 컴파일 클래스패스엔
// 영향이 없다 — 그래서 모든 Android 서브프로젝트에 실제로 이 의존성을
// 주입해야 한다.
subprojects {
    afterEvaluate {
        if (project.plugins.hasPlugin("com.android.library") || project.plugins.hasPlugin("com.android.application")) {
            dependencies.add("implementation", "androidx.concurrent:concurrent-futures:1.2.0")
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
