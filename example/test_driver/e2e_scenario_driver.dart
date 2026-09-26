// Driver for the e2e scenario integration test: forwards the
// `e2e-scenario:` milestone prints to the drive console and exits
// non-zero when the test fails.
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
