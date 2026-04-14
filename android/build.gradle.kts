allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val buildDirOverride = System.getenv("ZIPAPP_ANDROID_BUILD_DIR")
val newBuildDir: Directory =
    if (buildDirOverride != null) {
        layout.dir(providers.provider { file(buildDirOverride) }).get()
    } else {
        rootProject.layout.buildDirectory
            .dir("../../build")
            .get()
    }
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
