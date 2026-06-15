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
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Force JVM 17 on every Android-library subproject (e.g. receive_sharing_intent) so
// that compileXxxJavaWithJavac and compileXxxKotlin always agree on the same target.
// Without this, plugins that pin Java 11 in their own build.gradle clash with the
// Kotlin Gradle Plugin 2.x default of jvmTarget=17.
// Uses LibraryExtension (AGP 9.0.x non-parameterized library DSL; CommonExtension<*> and
// BaseExtension are both ERROR-level deprecated in AGP 9.x) and
// compilerOptions DSL (KGP 2.x; kotlinOptions.jvmTarget is DeprecationLevel.ERROR).
// NOTE: afterEvaluate CANNOT be used here because evaluationDependsOn(":app") in the
// block above forces :app to evaluate eagerly; afterEvaluate on an already-evaluated
// project throws InvalidUserCodeException in Gradle 9. Use plugins.withId() instead,
// which fires at the correct lifecycle point (when the plugin is applied, before
// evaluation completes). KotlinJvmCompile uses configureEach (already lazy) and does
// not need any evaluation wrapper.
subprojects {
    plugins.withId("com.android.library") {
        extensions.findByType<com.android.build.api.dsl.LibraryExtension>()
            ?.compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
    }
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinJvmCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
