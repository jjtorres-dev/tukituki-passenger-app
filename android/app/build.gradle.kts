import java.util.Properties

plugins {
    id("com.android.application")

    // The Flutter Gradle Plugin must be applied
    // after the Android plugin.
    id("dev.flutter.flutter-gradle-plugin")

    // PASSENGER-PUSH-R1: procesa android/app/google-services.json
    // (archivo real fuera de git, ver android/app/google-services.json.example).
    id("com.google.gms.google-services")
}

val localProperties = Properties()

val localPropertiesFile =
    rootProject.file("local.properties")

if (localPropertiesFile.exists()) {
    localPropertiesFile.inputStream().use {
        localProperties.load(it)
    }
}

val mapsApiKey =
    localProperties.getProperty(
        "MAPS_API_KEY",
        "",
    )

android {
    namespace = "pe.tukituki.passenger"

    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility =
            JavaVersion.VERSION_17

        targetCompatibility =
            JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId =
            "pe.tukituki.passenger"

        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion

        versionCode =
            flutter.versionCode

        versionName =
            flutter.versionName

        manifestPlaceholders[
            "MAPS_API_KEY"
        ] = mapsApiKey
    }

    buildTypes {
        release {
            signingConfig =
                signingConfigs.getByName(
                    "debug",
                )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget =
            org.jetbrains.kotlin.gradle.dsl
                .JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}