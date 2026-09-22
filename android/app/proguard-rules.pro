# google_mlkit_text_recognition references recognizer options for scripts
# (Chinese/Devanagari/Korean) this app doesn't declare a dependency on —
# only Latin (bundled by default) and Japanese (added above) are used, so
# those classes are never loaded at runtime; just silence R8's warning
# about them being missing instead of pulling in unused ML Kit modules.
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
