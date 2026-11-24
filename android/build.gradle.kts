allprojects {
    repositories {
        google()
        mavenCentral()
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

// [本機測試暫時停用，請勿提交] 這段會讓 flutter_facebook_auth 編譯時找不到 android.* 類別
// （Java 17 不接受 Java 8 用的 bootclasspath）。移除後 Facebook 套件可正常建置。待登入組員確認。
// gradle.projectsEvaluated {
//     rootProject.project(":flutter_facebook_auth")
//         .tasks.withType<org.gradle.api.tasks.compile.JavaCompile>()
//         .configureEach {
//             sourceCompatibility = "17"
//             targetCompatibility = "17"
//         }
// }