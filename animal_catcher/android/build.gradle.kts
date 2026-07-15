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
    // Force every plugin subproject to compile against a modern API level.
    // Some plugins (e.g. vibration) still pin compileSdk 33 internally, which fails
    // AAR metadata checks against androidx libraries that require API 34+.
    // Registered BEFORE evaluationDependsOn so the hook is added while the
    // subproject is still unevaluated.
    afterEvaluate {
        extensions.findByName("android")?.let { ext ->
            val androidExt = ext as com.android.build.gradle.BaseExtension
            val current = androidExt.compileSdkVersion?.substringAfter("android-")?.toIntOrNull()
            if (current == null || current < 36) {
                androidExt.compileSdkVersion(36)
            }
        }
    }
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
