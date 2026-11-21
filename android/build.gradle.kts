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

// 1. Inject namespace for plugins that lack one
subprojects {
    afterEvaluate {
        extensions.findByType<LibraryExtension>()?.apply {
            if (namespace == null) {
                namespace = "com.fasbec.plugins.${project.name}"
            }
        }
    }
}

// 2. Force ALL subprojects to use JVM 17 and compileSdk 37
subprojects {
    afterEvaluate {
        if (plugins.hasPlugin("com.android.library") || plugins.hasPlugin("com.android.application")) {
            extensions.findByType<BaseExtension>()?.apply {
                // Force plugins to compile against API 37
                compileSdkVersion(37) 
                
                compileOptions {
                    sourceCompatibility = JavaVersion.VERSION_17
                    targetCompatibility = JavaVersion.VERSION_17
                }
            }
        }
        tasks.withType<KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(JvmTarget.JVM_17)
            }
        }
        tasks.withType<JavaCompile>().configureEach {
            sourceCompatibility = "17"
            targetCompatibility = "17"
        }
    }
}

// 3. Auto-fix the telephony plugin's AndroidManifest.xml
subprojects {
    afterEvaluate {
        if (name == "telephony") {
            val manifestFile = file("src/main/AndroidManifest.xml")
            if (manifestFile.exists()) {
                val content = manifestFile.readText()
                val newContent = content.replace(Regex("""package="[^"]*""""), "")
                if (content != newContent) {
                    manifestFile.writeText(newContent)
                    println("✅ Auto-fixed telephony plugin AndroidManifest.xml")
                }
            }
        }
    }
}

// 4. Evaluate app project last
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}