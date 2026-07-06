// Conditional export: uses dart:io implementation when available, otherwise web stub.
export 'file_reader_io.dart' if (dart.library.html) 'file_reader_web.dart';
