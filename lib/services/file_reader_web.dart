import 'dart:typed_data';

Future<Uint8List> readFileBytes(String path) async {
  // On web we cannot read local filesystem paths. This stub throws so builds succeed;
  // calling code should use web file pickers to obtain bytes instead of file paths.
  throw UnsupportedError('readFileBytes is not supported on the web.');
}
