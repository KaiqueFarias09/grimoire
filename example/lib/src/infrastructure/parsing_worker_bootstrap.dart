import 'package:unseal/unseal.dart';

/// Points Unseal at the compiled parsing worker
/// (`web/unseal_worker.js`, built with
/// `dart compile js <unseal>/web/unseal_worker.dart -o web/unseal_worker.js`).
///
/// From here on `Unseal.read`, `readMetadata` and `BookSession.open`
/// run in the worker, with a silent fallback to the main thread when
/// the script is unreachable or workers are blocked.
void bootstrapParsingWorker() {
  UnsealWorker.configure(Uri.parse('unseal_worker.js'));
}
