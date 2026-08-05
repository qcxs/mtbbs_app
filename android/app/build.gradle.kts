import java.io.StringReader
import java.security.KeyStore
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 签名配置：key.properties 四项齐全且 key.jks 能成功加载才启用正式签名，
// 否则（无 key.properties / 文件缺失 / 密码错误）回退 debug 签名，构建不报错。
val keyProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) {
        // Java Properties.load 不识别 UTF-8 BOM，先按文本读入并剥掉首字符 BOM
        val text = f.readText(Charsets.UTF_8).removePrefix("\uFEFF")
        load(StringReader(text))
    }
}

// AGP 9 新 DSL 下 signingConfigs 只能在 android{} 块内访问，这里只做「能否用正式签名」的判定
val keystoreOk: Boolean = try {
    val storePath = keyProperties.getProperty("storeFile")
    val storePwd = keyProperties.getProperty("storePassword")
    val alias = keyProperties.getProperty("keyAlias")
    val keyPwd = keyProperties.getProperty("keyPassword")
    val ksFile = storePath?.let { file(it) }
    if (ksFile != null && ksFile.exists() &&
        !storePwd.isNullOrEmpty() && !alias.isNullOrEmpty() && !keyPwd.isNullOrEmpty()
    ) {
        // 预先加载 keystore 校验密码，避免问题拖到打包阶段才报错
        KeyStore.getInstance(KeyStore.getDefaultType()).apply {
            ksFile.inputStream().use { load(it, storePwd.toCharArray()) }
        }
        true
    } else {
        false
    }
} catch (e: Exception) {
    println("签名配置无效（${e.message}），回退 debug 签名")
    false
}

android {
    namespace = "com.github.qcxs.discuz"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        if (keystoreOk) {
            create("release") {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
                enableV1Signing = true
                enableV2Signing = true
            }
        }
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
            // 有正式签名用正式签名；否则用 debug 签名（本地自测/CI 未配 Secrets 均不报错）
            signingConfig = if (keystoreOk) signingConfigs.getByName("release")
            else signingConfigs.getByName("debug")
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
