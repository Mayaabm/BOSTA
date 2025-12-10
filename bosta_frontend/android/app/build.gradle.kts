plugins {
    // These plugins are required to build the Android app.
    
    id("com.android.application") 
    id("org.jetbrains.kotlin.android") 
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.bosta_frontend"
    compileSdk = 34

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.example.bosta_frontend"
        minSdk = flutter.minSdkVersion
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }
}


flutter {
    source = "../.."
}

dependencies {
    // You can add native Android dependencies here.
}
