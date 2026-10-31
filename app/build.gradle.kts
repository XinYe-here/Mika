import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
}

// 关于页上的构建编号:当前提交的短哈希;没有 git(如从源码包编译)时写 dev
val gitHash: String = runCatching {
    providers.exec { commandLine("git", "rev-parse", "--short=7", "HEAD") }.standardOutput.asText.get().trim()
}.getOrNull()?.takeIf { it.isNotEmpty() } ?: "dev"

// ---- 自维护包(dsh 分支)用的版本号与签名 ----
// 版本号是我们自己排的 major.minor.rev,和上游的 0.1.x 没关系;upstream* 只记录"代码基于上游哪个版本"。
// versionCode 用 major*10000+minor*100+rev,只增不减,保证永远能覆盖安装。
val dshProps = Properties().apply {
    val f = rootProject.file("dsh/version.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val dshMajor = (dshProps.getProperty("major") ?: "1").toInt()
val dshMinor = (dshProps.getProperty("minor") ?: "0").toInt()
val dshRev = (dshProps.getProperty("rev") ?: "0").toInt()
val dshVersionCode = dshMajor * 10000 + dshMinor * 100 + dshRev
val dshVersionName = "$dshMajor.$dshMinor.$dshRev"

// 签名信息放 local.properties(已在 .gitignore 里),不进仓库
val dshLocal = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val dshStoreFile = dshLocal.getProperty("dsh.storeFile") ?: ""
val dshStorePassword = dshLocal.getProperty("dsh.storePassword") ?: ""
val dshKeyAlias = dshLocal.getProperty("dsh.keyAlias") ?: "mika"
val dshKeyPassword = dshLocal.getProperty("dsh.keyPassword") ?: ""

android {
    namespace = "com.wangzan101.mika"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.wangzan101.mika"
        minSdk = 30
        targetSdk = 35
        // 自维护包:版本号自己排(major.minor.rev),versionCode = major*10000+minor*100+rev,只增不减
        versionCode = dshVersionCode
        versionName = dshVersionName
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        buildConfigField("String", "GIT_HASH", "\"$gitHash\"")
        // 关于页版本号后的 Beta 标记;出正式版时改成 false
        buildConfigField("boolean", "BETA", "true")
    }

    // 沙箱程序只有 arm64 版本(jniLibs/arm64-v8a);APK 不限 ABI,别的设备照常安装、显示「此设备不支持沙箱」。
    // 沙箱程序要从 nativeLibraryDir 直接执行,安装时必须解到磁盘
    packaging { jniLibs { useLegacyPackaging = true } }
    // 自带的运行环境(assets/runtime/rootfs.tar.xz,tools/sandbox/build-runtime.py 生成)已是 xz,不再压一遍
    androidResources { noCompress += "xz" }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // 评测任务集(仓库根目录 eval/tasks)打进测试包的 assets,真机评测跑器从那里读题
    sourceSets.getByName("androidTest").assets.srcDir(rootProject.file("eval/tasks"))

    // 自维护包的签名:信息在 local.properties 里(dsh.storeFile / dsh.storePassword / dsh.keyAlias / dsh.keyPassword)
    signingConfigs {
        create("personal") {
            if (dshStoreFile.isNotEmpty()) {
                storeFile = file(dshStoreFile)
                storePassword = dshStorePassword
                keyAlias = dshKeyAlias
                keyPassword = dshKeyPassword
            }
        }
    }

    buildTypes {
        // 看流畅度用的包:和发布版一样不可调试(调试包不做预先编译,界面慢好几倍,手感不作数),
        // 用本机调试签名,能直接覆盖调试包、保留数据;可被性能工具采样。./gradlew :app:assemblePerf
        create("perf") {
            initWith(getByName("release"))
            signingConfig = signingConfigs.getByName("debug")
            isProfileable = true
            matchingFallbacks += "release"
        }

        // 自维护包:用我们自己的 key 签(dsh 分支专用)。./gradlew :app:assemblePersonal
        create("personal") {
            initWith(getByName("release"))
            signingConfig = signingConfigs.getByName("personal")
            isProfileable = true
            matchingFallbacks += "release"
        }
    }

    buildFeatures {
        compose = true
        aidl = true
        buildConfig = true
    }
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    implementation(project(":core"))
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.material3)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.webkit)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.okhttp)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.xz)
    implementation(libs.commonmark)
    implementation(libs.commonmark.ext.gfm.tables)
    implementation(libs.commonmark.ext.gfm.strikethrough)
    // 两种识别模型都随 APK 安装；首次使用不依赖 Play 服务下载。
    implementation(libs.mlkit.text.recognition)
    implementation(libs.mlkit.text.recognition.chinese)

    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(libs.okhttp.mockwebserver)
    // 沙箱路径契约(core 的 testFixtures):AndroidSandbox 在 JVM 与真机上都跑同一套
    testImplementation(testFixtures(project(":core")))
    androidTestImplementation(testFixtures(project(":core")))

    androidTestImplementation(platform(libs.compose.bom))
    androidTestImplementation(libs.compose.ui.test.junit4)
    debugImplementation(libs.compose.ui.test.manifest)
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.androidx.test.ext.junit)
    androidTestImplementation(libs.junit)
}

// LicensesTest 读仓库根目录的 THIRD_PARTY_NOTICES.md:让它参与测试的增量判断
tasks.withType<Test>().configureEach {
    inputs.file(rootProject.file("THIRD_PARTY_NOTICES.md")).withPropertyName("thirdPartyNotices")
}
