import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Ключ загрузки Google Play. Сам ключ и пароли в репозиторий не входят:
// android/key.properties и ~/.android-keys/ — см. раздел «Google Play» в CLAUDE.md.
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasUploadKey = keyProperties.getProperty("storeFile") != null

android {
    namespace = "com.holybible.holy_bible"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // После первой публикации в Google Play не меняется.
        applicationId = "com.holybible.holy_bible"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasUploadKey) {
            create("upload") {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Без ключа релиз всё же собирается — чтобы `flutter run --release`
            // работал на любой машине, — но с отладочной подписью, и Google Play
            // такую сборку не примет.
            signingConfig = if (hasUploadKey) {
                signingConfigs.getByName("upload")
            } else {
                logger.warn("android/key.properties не найден: релиз подписан отладочным ключом и в Google Play не годится")
                signingConfigs.getByName("debug")
            }
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
