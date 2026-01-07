## Flutter-specific ProGuard/R8 rules for OM Messenger

# ============================================================================
# WHAT IS PROGUARD/R8?
# ============================================================================
# ProGuard/R8 is a code shrinker, optimizer, and obfuscator for Android.
# When building release APKs, it:
# 1. Removes unused code to make APK smaller
# 2. Obfuscates class/method names (com.example.UserService → a.b.c)
# 3. Optimizes bytecode for better performance
#
# PROBLEM: Sometimes it removes code that IS actually needed (via reflection)
# or renames classes that external libraries expect to find by name.
#
# SOLUTION: These rules tell R8 "Don't touch these classes/methods!"
# ============================================================================

## ============================================================================
## FLUTTER SECURE STORAGE
## ============================================================================
## This package stores sensitive data (tokens, passwords) encrypted in Android KeyStore
## It uses reflection to access Android crypto APIs - R8 must not obfuscate these

-keep class com.it_nomads.fluttersecurestorage.** { *; }
-dontwarn com.it_nomads.fluttersecurestorage.**

## Keep Android KeyStore classes (used for encryption)
-keep class javax.crypto.** { *; }
-keep class javax.crypto.spec.** { *; }
-keep class android.security.keystore.** { *; }


## ============================================================================
## DRIFT DATABASE (SQLite ORM)
## ============================================================================
## Drift generates code at compile-time but R8 might remove "unused" generated classes
## Keep all generated database classes and their methods

-keep class drift.** { *; }
-keep class **.$drift$** { *; }
-keep class **Database { *; }
-keep class **Dao { *; }

## SQLite native library
-keep class org.sqlite.** { *; }
-keep class org.sqlite.database.** { *; }


## ============================================================================
## CONNECTIVITY PLUS
## ============================================================================
## Monitors network state - uses Android system services via reflection

-keep class com.dexterous.** { *; }
-dontwarn com.dexterous.**


## ============================================================================
## HTTP & WEB SOCKETS
## ============================================================================
## Keep HTTP client and WebSocket classes for network communication

-keep class okhttp3.** { *; }
-keep class okio.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**

## WebSocket channel
-keep class io.flutter.plugins.** { *; }


## ============================================================================
## GSON/JSON SERIALIZATION
## ============================================================================
## If you use JSON serialization (jsonDecode/jsonEncode with model classes),
## keep your model classes so R8 doesn't rename their fields

-keep class com.ommessenger.om_mobile.models.** { *; }

## Keep all model classes in lib/models/ (Message, User, Conversation, etc.)
## R8 renames fields like "user_id" → "a", breaking JSON parsing
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}


## ============================================================================
## GENERAL FLUTTER RULES
## ============================================================================

## Keep Flutter engine classes
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

## Keep all native methods (called from Dart via platform channels)
-keepclassmembers class * {
    native <methods>;
}


## ============================================================================
## DEBUGGING (Remove in production if you want maximum obfuscation)
## ============================================================================

## Keep source file names and line numbers for crash reports
## Comment these out for maximum obfuscation (but harder to debug crashes)
-keepattributes SourceFile,LineNumberTable

## Keep generic signatures (for better crash reports)
-keepattributes Signature

## Keep annotations (some libraries need them)
-keepattributes *Annotation*


## ============================================================================
## WARNINGS SUPPRESSION
## ============================================================================
## Suppress warnings for missing classes that are only needed on specific platforms

-dontwarn javax.annotation.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
