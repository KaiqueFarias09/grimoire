// Driver for the integration scenarios. Fails when an assertion fails and
// writes `reportData` to build/integration_response_data.json on success.
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
