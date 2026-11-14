import 'package:bondbell/shared/widgets/common.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sizes below 0.1 MB read in KB, never "0.0 MB" (fix round, item 7)', () {
    expect(megabytes(0), '1 KB');
    expect(megabytes(1), '1 KB');
    expect(megabytes(14132), '14 KB');
    expect(megabytes(104857 - 1), '103 KB');
    expect(megabytes(104857), '0.1 MB');
    expect(megabytes(33606244), '32.0 MB');
  });
}
