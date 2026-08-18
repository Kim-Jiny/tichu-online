import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.jiny.tichuOnline"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"]?.toString()
            keyPassword = keystoreProperties["keyPassword"]?.toString()
            storeFile = keystoreProperties["storeFile"]?.toString()?.let { file(it) }
            storePassword = keystoreProperties["storePassword"]?.toString()
        }
    }

    defaultConfig {
        applicationId = "com.jiny.tichuOnline"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            // AGP 9 부터 릴리즈 기본값이 R8 켜짐으로 바뀌었다. 그대로 두면
            // 이 앱은 시작하자마자 죽는다: Room 이 리플렉션으로 만드는
            // WorkDatabase_Impl 의 기본 생성자가 제거돼
            // "Failed to create an instance of androidx.work.impl.WorkDatabase"
            // 로 androidx.startup 이 터진다(Play 사전 출시 검사에서 잡혔다.
            // 16KB 기기에서 보고됐지만 페이지 크기와는 무관하다).
            //
            // 3.0.1 까지 쓰던 동작으로 되돌린다. R8 을 켤 거라면 리플렉션을
            // 쓰는 라이브러리(Room·Firebase·카카오·Apple 로그인)마다 keep
            // 규칙을 갖추고 실기기로 확인한 뒤에 따로 해야 한다 - 릴리즈
            // 직전에 곁다리로 켤 일이 아니다.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}
