import com.android.build.gradle.BaseExtension
import com.android.build.gradle.LibraryExtension
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// 1. Inject namespace for plugins that lack one (fixes previous telephony error)
subprojects {
    afterEvaluate {
        extensions.findByType<LibraryExtension>()?.apply {
            if (namespace == null) {
                namespace = "com.fasbec.plugins.${project.name}"
            }
        }
    }
}

// 2. Force ALL subprojects (plugins) to use JVM 11 for Java & Kotlin
// This must run in afterEvaluate to override the plugin's own settings.
subprojects {
    afterEvaluate {
        // Force Android plugins to use JVM 11
        if (plugins.hasPlugin("com.android.library") || plugins.hasPlugin("com.android.application")) {
            configure<BaseExtension> {
                compileOptions {
                    sourceCompatibility = JavaVersion.VERSION_11
                    targetCompatibility = JavaVersion.VERSION_11
                }
            }
        }
        // Force Kotlin compilation to use JVM 11
        tasks.withType<KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(JvmTarget.JVM_11)
            }
        }
        // Force Java compilation to use JVM 11 (for non-Android subprojects)
        tasks.withType<JavaCompile>().configureEach {
            sourceCompatibility = "11"
            targetCompatibility = "11"
        }
    }
}

// 3. Evaluate app project last
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}