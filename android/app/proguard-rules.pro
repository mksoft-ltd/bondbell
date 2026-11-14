# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# flutter_local_notifications: scheduled notifications are persisted as
# Gson-serialised objects and read back after a reboot; R8 must not rename
# or strip their fields.
-keep class com.dexterous.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken

# Google Play Billing (in_app_purchase_android)
-keep class com.android.vending.billing.** { *; }
-keep class com.android.billingclient.** { *; }

# Play Core (deferred components) referenced by the Flutter embedding
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**
