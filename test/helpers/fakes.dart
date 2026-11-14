import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bondbell/core/constants/app_constants.dart';
import 'package:bondbell/features/draws/data/draw_source.dart';
import 'package:bondbell/features/draws/data/nsi_index.dart';
import 'package:bondbell/features/purchases/data/store_gateway.dart';
import 'package:bondbell/features/reminders/reminder_service.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// A stand-in for the native `in_app_purchase` plugin. Every outcome is
/// delivered the way the plugin delivers it: on [purchaseStream], after the
/// `buy*` call has merely reported that the sheet opened.
class FakeStoreGateway implements StoreGateway {
  FakeStoreGateway({
    this.available = true,
    Map<String, String>? prices,
  }) : prices = prices ?? defaultPrices;

  /// Deliberately odd prices so a test can tell the store's own string from
  /// anything hardcoded in the app.
  static const Map<String, String> defaultPrices = <String, String>{
    AppConstants.proProductId: '£4.79',
    AppConstants.tipSmallId: '£1.89',
    AppConstants.tipMediumId: '£4.89',
    AppConstants.tipLargeId: '£9.89',
  };

  final StreamController<List<PurchaseDetails>> _stream =
      StreamController<List<PurchaseDetails>>.broadcast();

  bool available;

  /// Products the store "has". Ids missing here come back in notFoundIDs.
  Map<String, String> prices;
  Object? queryError;
  bool buyStarts = true;
  Object? buyError;

  /// What [restorePurchases] puts on the stream (nothing by default).
  List<PurchaseDetails> Function()? onRestore;

  /// Called inside [completePurchase], before it is recorded.
  void Function(PurchaseDetails)? onComplete;

  final List<String> nonConsumableBuys = <String>[];
  final List<String> consumableBuys = <String>[];
  final List<PurchaseDetails> completed = <PurchaseDetails>[];
  int restoreCalls = 0;
  int queryCalls = 0;

  void emit(List<PurchaseDetails> list) => _stream.add(list);
  void emitError(Object e) => _stream.addError(e);
  Future<void> close() => _stream.close();

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _stream.stream;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async {
    queryCalls++;
    final Object? e = queryError;
    if (e != null) throw e;
    return ProductDetailsResponse(
      productDetails: <ProductDetails>[
        for (final String id in ids)
          if (prices[id] != null) product(id, prices[id]!),
      ],
      notFoundIDs: <String>[
        for (final String id in ids)
          if (prices[id] == null) id,
      ],
    );
  }

  @override
  Future<bool> buyNonConsumable(ProductDetails product) async {
    nonConsumableBuys.add(product.id);
    final Object? e = buyError;
    if (e != null) throw e;
    return buyStarts;
  }

  @override
  Future<bool> buyConsumable(ProductDetails product) async {
    consumableBuys.add(product.id);
    final Object? e = buyError;
    if (e != null) throw e;
    return buyStarts;
  }

  @override
  Future<void> restorePurchases() async {
    restoreCalls++;
    final List<PurchaseDetails>? l = onRestore?.call();
    if (l != null && l.isNotEmpty) emit(l);
  }

  @override
  Future<void> completePurchase(PurchaseDetails details) async {
    onComplete?.call(details);
    completed.add(details);
  }

  static ProductDetails product(String id, String price) => ProductDetails(
    id: id,
    title: id,
    description: id,
    price: price,
    rawPrice: 0,
    currencyCode: 'GBP',
  );
}

/// One purchase update as the plugin would deliver it.
PurchaseDetails purchaseUpdate(
  String productId,
  PurchaseStatus status, {
  bool pendingComplete = true,
  String? errorMessage,
}) {
  final PurchaseDetails p = PurchaseDetails(
    purchaseID: 'order-$productId-${status.name}',
    productID: productId,
    verificationData: PurchaseVerificationData(
      localVerificationData: '',
      serverVerificationData: '',
      source: 'test',
    ),
    transactionDate: '0',
    status: status,
  )..pendingCompletePurchase = pendingComplete;
  if (errorMessage != null) {
    p.error = IAPError(source: 'test', code: 'purchase_error', message: errorMessage);
  }
  return p;
}

/// Reminder service that records instead of touching the OS.
class FakeReminderService implements ReminderService {
  FakeReminderService({this.grant = true});
  bool grant;
  int permissionRequests = 0;
  int schedules = 0;
  int cancels = 0;

  @override
  Future<void> init() async {}
  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return grant;
  }

  @override
  Future<void> scheduleUpcoming() async => schedules++;
  @override
  Future<void> cancelAll() async => cancels++;
}

/// The two NS&I draws and the unclaimed list, as a downloads page would
/// list them.
NsiIndex testIndex({int draws = 2}) => NsiIndex(
  draws: <RemoteList>[
    for (int i = 0; i < draws; i++)
      RemoteList(
        id: '2026-${(11 - i).toString().padLeft(2, '0')}',
        label: '${const <String>['November', 'October', 'September', 'August', 'July', 'June'][i]} 2026',
        url: Uri.parse('https://www.nsandi.com/files/d$i.zip'),
      ),
  ],
  unclaimed: RemoteList(
    id: 'unclaimed',
    label: 'Unclaimed prizes',
    url: Uri.parse('https://www.nsandi.com/files/u.zip'),
  ),
);

/// A [DrawSource] whose every step is scriptable, and which records every
/// file it hands out so tests can prove it was deleted afterwards.
class ScriptedSource implements DrawSource {
  ScriptedSource(this.dir, {NsiIndex? index}) : index = index ?? testIndex();

  final Directory dir;
  NsiIndex index;
  Object? indexError;

  /// Bytes for each list id; falls back to [defaultZip].
  final Map<String, List<int>> zips = <String, List<int>>{};
  List<int>? defaultZip;
  Object? downloadError;

  /// When set, download writes a partial file and waits on this before
  /// finishing (or throws if cancelled meanwhile).
  Completer<void>? hold;
  final List<File> handedOut = <File>[];
  final List<File> partials = <File>[];
  int fetches = 0;

  @override
  bool get isSample => false;

  @override
  Future<NsiIndex> fetchIndex() async {
    fetches++;
    final Object? e = indexError;
    if (e != null) throw e;
    return index;
  }

  @override
  Future<int?> sizeOf(RemoteList list) async =>
      (zips[list.id] ?? defaultZip)?.length;

  @override
  Future<File> download(
    RemoteList list, {
    void Function(int received, int? total)? onProgress,
    DownloadCancel? cancel,
  }) async {
    final Object? e = downloadError;
    if (e != null) throw e;
    final List<int> bytes = zips[list.id] ?? defaultZip!;
    final File f = File('${dir.path}/${list.id}-${handedOut.length}.zip');
    final Completer<void>? h = hold;
    if (h != null) {
      // Half the file is on disk while we "wait for the network".
      f.writeAsBytesSync(bytes.sublist(0, bytes.length ~/ 2));
      partials.add(f);
      onProgress?.call(bytes.length ~/ 2, bytes.length);
      cancel?.onCancel(() {
        if (!h.isCompleted) h.complete();
      });
      await h.future;
      if (cancel?.isCancelled ?? false) {
        if (f.existsSync()) f.deleteSync();
        throw const DownloadCancelledException();
      }
    }
    f.writeAsBytesSync(bytes);
    handedOut.add(f);
    onProgress?.call(bytes.length, bytes.length);
    return f;
  }
}

/// Writes a minimal single-entry ZIP (deflate or stored), the shape NS&I
/// publishes, from synthetic text. Never NS&I data.
List<int> buildZip(String name, String text, {bool deflate = true}) {
  final List<int> content = latin1.encode(text);
  final List<int> data = deflate
      ? ZLibEncoder(raw: true, level: 6).convert(content)
      : content;
  final List<int> nameBytes = latin1.encode(name);
  final int crc = _crc32(content);
  final int method = deflate ? 8 : 0;
  final BytesBuilder b = BytesBuilder();
  void u16(int v) => b.add(<int>[v & 0xff, (v >> 8) & 0xff]);
  void u32(int v) => b.add(<int>[
    v & 0xff,
    (v >> 8) & 0xff,
    (v >> 16) & 0xff,
    (v >> 24) & 0xff,
  ]);
  // Local file header.
  u32(0x04034b50);
  u16(20);
  u16(0);
  u16(method);
  u16(0);
  u16(0);
  u32(crc);
  u32(data.length);
  u32(content.length);
  u16(nameBytes.length);
  u16(0);
  b.add(nameBytes);
  b.add(data);
  final int cdOffset = b.length;
  // Central directory.
  u32(0x02014b50);
  u16(20);
  u16(20);
  u16(0);
  u16(method);
  u16(0);
  u16(0);
  u32(crc);
  u32(data.length);
  u32(content.length);
  u16(nameBytes.length);
  u16(0);
  u16(0);
  u16(0);
  u16(0);
  u32(0);
  u32(0);
  b.add(nameBytes);
  final int cdSize = b.length - cdOffset;
  // End of central directory.
  u32(0x06054b50);
  u16(0);
  u16(0);
  u16(1);
  u16(1);
  u32(cdSize);
  u32(cdOffset);
  u16(0);
  return b.toBytes();
}

int _crc32(List<int> bytes) {
  int crc = 0xFFFFFFFF;
  for (final int byte in bytes) {
    crc ^= byte;
    for (int k = 0; k < 8; k++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}

/// A winners file in NS&I's measured layout: heading, notes total, tier
/// table, then `Part` sections of right-aligned numbers, 8 per line.
/// [tiers] maps prize → numbers drawn for it. [claimedTierCounts] lets a
/// test print a tier table that disagrees with the numbers that follow.
String winnersFile(
  Map<int, List<String>> tiers, {
  String month = 'November 2026',
  Map<int, int>? claimedTierCounts,
  int? claimedTotal,
}) {
  final StringBuffer s = StringBuffer();
  final int total = tiers.values.fold(0, (int a, List<String> l) => a + l.length);
  String money(int v) => '£${v.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (Match m) => '${m[1]},')}';
  const List<String> roman = <String>['I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X', 'XI'];
  final List<int> prizes = tiers.keys.toList()..sort((int a, int b) => b.compareTo(a));
  s.writeln('_' * 60);
  s.writeln('PREMIUM BOND PRIZE DRAW                                  $month');
  s.writeln('Notes:');
  s.writeln('(i)  The amount for distribution is £1 which gives a total of '
      '${claimedTotal ?? total} prizes.');
  for (int i = 0; i < prizes.length; i++) {
    final int p = prizes[i];
    final int n = claimedTierCounts?[p] ?? tiers[p]!.length;
    s.writeln('| ${roman[i]}.   $n prizes of ${money(p)}      |');
  }
  for (int i = 0; i < prizes.length; i++) {
    final int p = prizes[i];
    s.writeln('');
    s.writeln('        Part ${roman[i]} - Numbers drawn for Prizes of ${money(p)} each ');
    s.writeln('');
    final List<String> nums = tiers[p]!;
    for (int j = 0; j < nums.length; j += 8) {
      s.writeln(nums
          .sublist(j, j + 8 > nums.length ? nums.length : j + 8)
          .map((String n) => n.padLeft(11))
          .join(' '));
      if (j % 40 == 32) {
        s.writeln('                                     Page No. ${j ~/ 40 + 2}');
        s.writeln('        Part ${roman[i]} - Prizes of ${money(p)} each (contd.)');
      }
    }
  }
  return s.toString().replaceAll('\n', '\r\n');
}
