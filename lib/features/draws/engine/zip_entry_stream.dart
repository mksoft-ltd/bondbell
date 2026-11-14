import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Streams the uncompressed bytes of the first file inside a ZIP archive
/// without ever holding the whole entry in memory.
///
/// NS&I publishes each list as a single-entry ZIP (Nov 2026: 33.6MB holding
/// an 82MB text file). The central directory at the end of the archive gives
/// the entry's compressed size and offset; the deflate data is then piped
/// through a raw [ZLibDecoder] chunk by chunk.
class ZipEntryStream {
  ZipEntryStream._(this.name, this.compressedSize, this.uncompressedSize,
      this._dataOffset, this._method, this._file);

  final String name;
  final int compressedSize;
  final int uncompressedSize;
  final int _dataOffset;
  final int _method;
  final File _file;

  static Future<ZipEntryStream> open(File file) async {
    final RandomAccessFile raf = await file.open();
    try {
      final int length = await raf.length();
      if (length < 22) throw const ZipFormatException('File is too small.');
      // End of central directory: last 22 bytes plus up to 64KB of comment.
      final int tailLen = length < 22 + 65535 ? length : 22 + 65535;
      await raf.setPosition(length - tailLen);
      final Uint8List tail = await raf.read(tailLen);
      int eocd = -1;
      for (int i = tail.length - 22; i >= 0; i--) {
        if (_u32(tail, i) == 0x06054b50) {
          eocd = i;
          break;
        }
      }
      if (eocd < 0) throw const ZipFormatException('Not a ZIP file.');
      final int entries = _u16(tail, eocd + 10);
      final int cdOffset = _u32(tail, eocd + 16);
      if (entries < 1) throw const ZipFormatException('The ZIP is empty.');
      if (cdOffset == 0xFFFFFFFF) {
        throw const ZipFormatException('ZIP64 archives are not supported.');
      }
      await raf.setPosition(cdOffset);
      final Uint8List cd = await raf.read(46);
      if (cd.length < 46 || _u32(cd, 0) != 0x02014b50) {
        throw const ZipFormatException('Bad central directory.');
      }
      final int method = _u16(cd, 10);
      final int compSize = _u32(cd, 20);
      final int uncompSize = _u32(cd, 24);
      final int nameLen = _u16(cd, 28);
      final int localOffset = _u32(cd, 42);
      final Uint8List nameBytes = await raf.read(nameLen);
      await raf.setPosition(localOffset);
      final Uint8List lh = await raf.read(30);
      if (lh.length < 30 || _u32(lh, 0) != 0x04034b50) {
        throw const ZipFormatException('Bad local header.');
      }
      final int dataOffset =
          localOffset + 30 + _u16(lh, 26) + _u16(lh, 28);
      if (method != 0 && method != 8) {
        throw ZipFormatException('Unsupported compression method $method.');
      }
      if (dataOffset + compSize > length) {
        throw const ZipFormatException('The ZIP is truncated.');
      }
      return ZipEntryStream._(String.fromCharCodes(nameBytes), compSize,
          uncompSize, dataOffset, method, file);
    } finally {
      await raf.close();
    }
  }

  /// The entry's bytes. [onCompressedBytes] reports progress through the
  /// compressed data, which is what the user waits on.
  Stream<List<int>> bytes({void Function(int read)? onCompressedBytes}) {
    int read = 0;
    final Stream<List<int>> raw = _file
        .openRead(_dataOffset, _dataOffset + compressedSize)
        .map((List<int> chunk) {
          read += chunk.length;
          onCompressedBytes?.call(read);
          return chunk;
        });
    if (_method == 0) return raw;
    return raw.transform(ZLibDecoder(raw: true));
  }

  static int _u16(Uint8List b, int o) => b[o] | (b[o + 1] << 8);
  static int _u32(Uint8List b, int o) =>
      b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);
}

class ZipFormatException implements Exception {
  const ZipFormatException(this.message);
  final String message;
  @override
  String toString() => 'ZipFormatException: $message';
}
