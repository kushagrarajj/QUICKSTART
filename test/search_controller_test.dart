import 'package:flutter_test/flutter_test.dart';
import 'package:quickkart/features/search/search_controller.dart';

import 'helpers/test_harness.dart';

void main() {
  late TestHarness h;

  setUp(() => h = TestHarness());
  tearDown(() => h.dispose());

  test('a slower earlier search cannot replace newer results', () async {
    h.server.chaos.latencyOverride = (request) {
      if (request.path == '/v1/products/search' && request.query['q'] == 'mi') {
        return const Duration(milliseconds: 50);
      }
      return Duration.zero;
    };
    final controller = h.read(searchControllerProvider.notifier);

    final earlier = controller.search('mi');
    final later = controller.search('chips');
    await Future.wait([earlier, later]);

    expect(controller.state.query, 'chips');
    expect(controller.state.results, isNotEmpty);
    expect(
        controller.state.results
            .every((product) => product.name.toLowerCase().contains('chips')),
        isTrue);
  });
}
