import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}
val releaseSigningConfigured =
    listOf("keyAlias", "keyPassword", "storeFile", "storePassword").all {
        !keystoreProperties.getProperty(it).isNullOrBlank()
    } && file(keystoreProperties.getProperty("storeFile")).isFile

// Reject every release task before execution when signing is unavailable.
// Debug builds and IDE project configuration remain usable without a keystore.
gradle.taskGraph.whenReady {
    if (allTasks.any { it.project == project && it.name.contains("Release") }) {
        check(releaseSigningConfigured) {
            "Release signing is required. Configure android/key.properties with " +
                "keyAlias, keyPassword, storeFile and storePassword, and an existing keystore."
        }
    }
}

android {
    namespace = "com.pjpv.zremote"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.pjpv.zremote"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningConfigured) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            if (releaseSigningConfigured) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
