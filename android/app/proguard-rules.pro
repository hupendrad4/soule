# Soulo ProGuard Rules
-keepattributes *Annotation*
-keepclassmembers class * {
    @kotlinx.serialization.Serializable *;
}
-keep class com.soulo.app.models.** { *; }
-dontwarn com.microsoft.onnxruntime.**
