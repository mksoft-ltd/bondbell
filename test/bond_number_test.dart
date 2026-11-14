import 'package:bondbell/features/bonds/domain/bond_number.dart';
import 'package:bondbell/features/bonds/domain/holder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BondNumber.tryParse accepts every format seen in NS&I files', () {
    for (final String s in <String>[
      '688ZY673096', // 3-digit prefix (modern)
      '85LV272879', // 2-digit prefix
      '3JA171611', // 1-digit prefix
      'DW369715', // no prefix (oldest certificates)
    ]) {
      test(s, () {
        final BondNumberResult r = BondNumber.tryParse(s);
        expect(r.error, isNull);
        expect(r.value.toString(), s);
      });
    }

    test('normalises case, spaces and separators from certificates', () {
      expect(BondNumber.tryParse(' 12 ab 345678 ').value.toString(),
          '12AB345678');
      expect(BondNumber.tryParse('12-AB-345678').value.toString(),
          '12AB345678');
    });
  });

  group('BondNumber.tryParse explains bad input', () {
    String? err(String s) => BondNumber.tryParse(s).error;

    test('empty', () => expect(err(''), contains('Enter')));
    test('holder number', () => expect(err('1234567890'), contains('holder')));
    test('letter O hint', () => expect(err('12AO345678'), contains('number 0')));
    test('letter I hint', () => expect(err('12IA345678'), contains('number 1')));
    test('letter U', () => expect(err('12UA345678'), contains('I, O or U')));
    test('one letter', () => expect(err('12A345678'), contains('two letters')));
    test('five digits', () => expect(err('12AB34567'), contains('six digits')));
    test('four-digit prefix',
        () => expect(err('1234AB345678'), contains('at most three')));
    test('leading zero', () => expect(err('012AB345678'), contains('start with 0')));
    test('symbols', () => expect(err('12AB34567#'), contains('only letters')));
  });

  group('BondRange.validate', () {
    test('single bond when end is blank', () {
      final RangeResult r = BondRange.validate('688ZY673096', '');
      expect(r.error, isNull);
      expect(r.start, r.end);
    });

    test('a statement range', () {
      final RangeResult r = BondRange.validate('688ZY673000', '688ZY673999');
      expect(r.error, isNull);
      final BondRange range =
          BondRange(id: 'x', start: r.start!, end: r.end!);
      expect(range.count, 1000);
      expect(range.contains(BondNumber.parse('688ZY673500')), isTrue);
      expect(range.contains(BondNumber.parse('688ZY674000')), isFalse);
      expect(range.contains(BondNumber.parse('688ZX673500')), isFalse);
    });

    test('rejects a range crossing series', () {
      expect(BondRange.validate('688ZY673000', '689ZY673999').error,
          contains('start the same way'));
    });

    test('rejects a reversed range', () {
      expect(BondRange.validate('688ZY673999', '688ZY673000').error,
          contains('Swap'));
    });
  });

  test('Holder JSON round trip keeps ranges and totals', () {
    final Holder h = Holder(id: 'h', name: 'Gran', ranges: <BondRange>[
      BondRange(
        id: 'r',
        start: BondNumber.parse('47DW185520'),
        end: BondNumber.parse('47DW185569'),
      ),
    ]);
    final Holder back = Holder.fromJson(h.toJson());
    expect(back, h);
    expect(back.totalValue, 50);
  });
}
