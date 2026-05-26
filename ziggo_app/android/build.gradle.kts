allprojects {
    repositories {
        google()
        mavenCentral()
        // PayHere Android SDK (com.github.PayHereDevs:payhere-android-sdk) is
        // published on JitPack, not Maven Central. Required by the
        // payhere_mobilesdk_flutter plugin.
        maven { url = uri("https://jitpack.io") }
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
