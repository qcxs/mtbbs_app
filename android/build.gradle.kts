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

// flutter_js 0.8.7 属旧式插件：android/build.gradle 里写死 kotlinOptions.jvmTarget = 1.8，
// 与 AGP 9 给 Java 编译任务的默认目标（11）不一致，Gradle 9 会直接报
// "Inconsistent JVM Target Compatibility Between Java and Kotlin Tasks" 而构建失败。
// 这里把它的 Kotlin jvmTarget 对齐到 11（仅作用于该插件，其余插件不受影响）。
subprojects {
    if (name == "flutter_js") {
        afterEvaluate {
            tasks
                .withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile::class.java)
                .configureEach {
                    compilerOptions.jvmTarget.set(
                        org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11,
                    )
                }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
