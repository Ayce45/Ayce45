# Minification is disabled for both build types; rules kept for a future opt-in.
# kotlinx.serialization
-keepattributes *Annotation*, InnerClasses
-keepclassmembers class dev.ayce.dailydev.** {
    *** Companion;
}
-keepclasseswithmembers class dev.ayce.dailydev.** {
    kotlinx.serialization.KSerializer serializer(...);
}
