// Driver for the scanned-archive reading e2e (DjVu + TIFF). Fails when
// an assertion fails and writes the test's `reportData` to
// build/integration_scanned_reading.json on success — the same
// convention as the other integration drivers, with a scenario-specific
// filename so artifacts never overwrite each other.
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) =>
      writeResponseData(data, testOutputFilename: 'integration_scanned_reading'),
);
