import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing key (docs/android-release.md). No Play Store: every APK must be signed with the
// same key, or Android refuses to install it over the previous version. Read from
// android/key.properties (never committed) or from VIXEO_KEYSTORE_* environment variables (CI).
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) FileInputStream(file).use { load(it) }
}

fun signingValue(property: String, variable: String): String? =
    keyProperties.getProperty(property) ?: System.getenv(variable)

val releaseStoreFile = signingValue("storeFile", "VIXEO_KEYSTORE_PATH")

android {
    namespace = "app.vixeo.vixeo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.vixeo.vixeo"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseStoreFile != null) {
            create("release") {
                storeFile = file(releaseStoreFile)
                storePassword = signingValue("storePassword", "VIXEO_KEYSTORE_PASSWORD")
                keyAlias = signingValue("keyAlias", "VIXEO_KEY_ALIAS")
                keyPassword = signingValue("keyPassword", "VIXEO_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
        }
    }
}

// A release APK without the release key would be impossible to update: stop the build instead.
gradle.taskGraph.whenReady {
    val releaseTask = allTasks.any { task ->
        task.project == project && task.name.contains("Release") &&
            (task.name.startsWith("assemble") || task.name.startsWith("bundle") || task.name.startsWith("package"))
    }
    if (releaseTask && releaseStoreFile == null) {
        throw GradleException(
            "Clé de release absente : créez android/key.properties ou les variables VIXEO_KEYSTORE_* " +
                "(voir docs/android-release.md)."
        )
    }
}

dependencies {
    // FileProvider: hands the downloaded APK to Android's installer (MainActivity).
    implementation("androidx.core:core-ktx:1.13.1")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
