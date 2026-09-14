/// The working copy of a scanned receipt.
///
/// Both the camera and the gallery picker hand back a file in the app's own
/// cache directory. The gallery one is a copy, so removing it never touches
/// the user's own photo. Nothing needs either file once the text has been
/// read, and leaving them there means a full-resolution photograph of every
/// receipt ever scanned sits on the phone indefinitely, untouched by
/// "Clear all data".
library;

export 'photo_cache_stub.dart' if (dart.library.io) 'photo_cache_io.dart';
