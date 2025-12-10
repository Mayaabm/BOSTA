import java.io.File

pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }

    val flutterSdkPath = run {
        val properties = java.util.Properties()
        val localPropertiesFile = File(settings.rootDir, "local.properties")
        if (localPropertiesFile.exists()) {
            properties.load(localPropertiesFile.inputStream())
        }
        properties.getProperty("flutter.sdk") ?: throw GradleException(
            "Flutter SDK not found. Define location in local.properties."
        )
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    plugins {
        id("com.android.application") version "8.2.1"
        id("org.jetbrains.kotlin.android") version "1.9.22"  // Add this line
    }
}

plugins {
    id("dev.flutter.flutter-gradle-plugin") version "1.0.0" apply false
}

include(":app")

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}