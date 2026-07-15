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
// Force compileSdk 36 for all subprojects to satisfy AAR metadata requirements
// (e.g. flutter_plugin_android_lifecycle requires compileSdk >= 36)
subprojects {
    afterEvaluate {
        project.extensions.findByType(com.android.build.api.dsl.LibraryExtension::class.java)?.let {
            it.compileSdk = 36
        }
        project.extensions.findByType(com.android.build.api.dsl.ApplicationExtension::class.java)?.let {
            it.compileSdk = 36
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
