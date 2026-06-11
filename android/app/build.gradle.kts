plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.serialization")
    id("org.jetbrains.kotlin.plugin.compose")
}

val keystoreProps by lazy {
    val f = rootProject.file("keystore.properties")
    if (f.exists()) {
        val map = mutableMapOf<String, String>()
        f.forEachLine { line ->
            val idx = line.indexOf('=')
            if (idx > 0 && !line.startsWith("#")) {
                map[line.substring(0, idx).trim()] = line.substring(idx + 1).trim()
            }
        }
        map
    } else null
}

android {
    namespace = "com.soulo.app"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.soulo.app"
        minSdk = 26
        targetSdk = 35
        versionCode = project.findProperty("SOULO_VERSION_CODE")?.toString()?.toIntOrNull() ?: 1
        versionName = "${project.findProperty("SOULO_VERSION_MAJOR") ?: "1"}.${project.findProperty("SOULO_VERSION_MINOR") ?: "0"}.${project.findProperty("SOULO_VERSION_PATCH") ?: "0"}"

        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a")
        }

        externalNativeBuild {
            cmake {
                arguments += "-DANDROID_STL=c++_shared"
                cppFlags += "-O3 -ffast-math"
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    buildFeatures {
        compose = true
    }

    signingConfigs {
        create("release") {
            val p = keystoreProps
            if (p != null) {
                storeFile = rootProject.file(p["storeFile"] ?: "none")
                storePassword = p["storePassword"]
                keyAlias = p["keyAlias"]
                keyPassword = p["keyPassword"]
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            if (keystoreProps != null) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
        jniLibs {
            useLegacyPackaging = true
        }
    }
}

dependencies {
    // Compose BOM
    val composeBom = platform("androidx.compose:compose-bom:2024.12.01")
    implementation(composeBom)

    // Core
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.activity:activity-compose:1.9.3")

    // Compose UI
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.navigation:navigation-compose:2.8.5")

    // Serialization
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")

    // SQLite
    implementation("androidx.sqlite:sqlite:2.4.0")
    implementation("androidx.sqlite:sqlite-framework:2.4.0")

    // Play Review
    implementation("com.google.android.play:review-ktx:2.0.2")

    // Security
    implementation("androidx.security:security-crypto:1.1.0-alpha06")

    // Coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")

    // Play Billing
    implementation("com.android.billingclient:billing-ktx:7.1.1")

    // ONNX Runtime
    implementation("com.microsoft.onnxruntime:onnxruntime-android:${project.findProperty("ONNXRUNTIME_VERSION") ?: "1.21.0"}")

    // Stripe (optional - requires maven.stripe.com repo)
    // implementation("com.stripe:stripe-android:21.2.2")

    // Testing
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
}
