allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    // 各プラグインモジュールの compileSdk を 36 に引き上げる。
    // flutter_plugin_android_lifecycle が android-36 を要求する一方、一部プラグイン
    // (file_picker 等)は android-34 でコンパイルされ AAR メタデータ検査に失敗する。
    // ルートスクリプトに AGP 型を持ち込まずに済むようリフレクションで設定する。
    // (evaluationDependsOn による早期評価より前に afterEvaluate を登録する必要がある)
    afterEvaluate {
        val androidExtension = extensions.findByName("android")
        if (androidExtension != null) {
            val setter = androidExtension.javaClass.methods.firstOrNull { m ->
                (m.name == "setCompileSdk" || m.name == "compileSdkVersion") &&
                    m.parameterTypes.size == 1 &&
                    (m.parameterTypes[0] == Int::class.javaPrimitiveType ||
                        m.parameterTypes[0] == Integer::class.java)
            }
            setter?.invoke(androidExtension, 36)
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
