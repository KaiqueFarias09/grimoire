// Driver for the real-reader opening probe. Fails when an assertion
// fails and writes the probe's `reportData` to
// build/integration_open_probe.json on success — the same convention
// as e2e_scenario_driver.dart's integration_response_data.json, with a
// probe-specific filename so A/B artifacts never overwrite each other.
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) =>
      writeResponseData(data, testOutputFilename: 'integration_open_probe'),
);
