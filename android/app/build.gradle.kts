plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 读取 key.properties（存在则正式签名；不存在回退 debug 签名，便于本地跑 release）
val keyProperties = Properties().also {
    val f = rootProject.file("key.properties")
    if (f.exists()) it.load(f.inputStream())
}

val releaseSigning = keyProperties.getProperty("storeFile")?.let {
    signingConfigs.create("release") {
        storeFile = file(it)
        storePassword = keyProperties.getProperty("storePassword")
        keyAlias = keyProperties.getProperty("keyAlias")
        keyPassword = keyProperties.getProperty("keyPassword")
        enableV1Signing = true
        enableV2Signing = true
    }
}

android {
    namespace = "com.github.qcxs.discuz"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.github.qcxs.discuz"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
        }
        release {
            // 有 key.properties（正式签名）用正式签名；否则用 debug 签名
            signingConfig = releaseSigning ?: signingConfigs.getByName("debug")
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
