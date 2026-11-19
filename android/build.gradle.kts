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
// flutter_js (JavaScript engine of the plug-in scrapers) sets Kotlin to JVM 1.8 but leaves Java at 11:
// Gradle refuses the mismatch. Put its Java side on 1.8 too (a JDK 17 still compiles it).
subprojects {
    if (name == "flutter_js") {
        val alignJava = {
            extensions.findByName("android")?.withGroovyBuilder {
                "compileOptions" {
                    setProperty("sourceCompatibility", JavaVersion.VERSION_1_8)
                    setProperty("targetCompatibility", JavaVersion.VERSION_1_8)
                }
            }
            Unit
        }
        if (state.executed) alignJava() else afterEvaluate { alignJava() }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
