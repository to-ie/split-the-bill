# The ML Kit text recognition plugin can build recognisers for Latin, Chinese,
# Devanagari, Japanese and Korean scripts. We only depend on the Latin one
# (see MlKitOcrEngine), so the other four artifacts are not on the classpath
# and R8 finds dangling references to them.
#
# Telling R8 not to warn is the correct resolution rather than pulling in four
# unused models: it keeps the APK small and the app never calls those paths.
# If a non-Latin script is ever needed, add the artifact and drop the matching
# line here.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# ML Kit loads its recogniser and the native OCR pipeline reflectively, so R8
# cannot see those references and is free to strip or rename them. That
# produces a release build where scanning throws while the debug build is
# fine. Keep the lot: it costs a little size and removes a whole class of
# release-only failure.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-keep class com.google_mlkit_text_recognition.** { *; }
-keep class com.google.android.odml.** { *; }
