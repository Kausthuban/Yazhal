import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// A bounded synchronous SDK bridge on an isolated worker. HTTP remains async
/// on the host isolate; no UI thread waits for JavaScript or network operations.
class ExtensionRpcSocket {
  ExtensionRpcSocket() {
    if (!Platform.isAndroid && !Platform.isLinux)
      throw UnsupportedError(
        'JavaScript extension runtime currently supports Android and Linux',
      );
  }
  static final _lib = Platform.isAndroid
      ? DynamicLibrary.open('libc.so')
      : DynamicLibrary.process();
  static final _pair = _lib
      .lookupFunction<
        Int32 Function(Int32, Int32, Int32, Pointer<Int32>),
        int Function(int, int, int, Pointer<Int32>)
      >('socketpair');
  static final _read = _lib
      .lookupFunction<
        IntPtr Function(Int32, Pointer<Uint8>, IntPtr),
        int Function(int, Pointer<Uint8>, int)
      >('read');
  static final _send = _lib
      .lookupFunction<
        IntPtr Function(Int32, Pointer<Uint8>, IntPtr, Int32),
        int Function(int, Pointer<Uint8>, int, int)
      >('send');
  static final _close = _lib
      .lookupFunction<Int32 Function(Int32), int Function(int)>('close');
  static final _shutdown = _lib
      .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
        'shutdown',
      );
  static const maxBytes = 4 * 1024 * 1024;
  List<int> create() {
    final ptr = calloc<Int32>(2);
    try {
      if (_pair(1, 1, 0, ptr) != 0)
        throw const SocketException('Could not open extension bridge');
      return [ptr[0], ptr[1]];
    } finally {
      calloc.free(ptr);
    }
  }

  void stop(int fd) {
    _shutdown(fd, 2);
  }

  void close(int fd) {
    _close(fd);
  }

  void write(int fd, List<int> bytes) {
    if (bytes.length > maxBytes)
      throw const FormatException('Extension response exceeds 4 MiB');
    final message = Uint8List(4 + bytes.length);
    ByteData.sublistView(message).setUint32(0, bytes.length);
    message.setRange(4, message.length, bytes);
    final ptr = calloc<Uint8>(message.length);
    try {
      ptr.asTypedList(message.length).setAll(0, message);
      var sent = 0;
      while (sent < message.length) {
        final n = _send(
          fd,
          ptr + sent,
          message.length - sent,
          Platform.isMacOS ? 0 : 0x4000,
        );
        if (n <= 0) throw const SocketException('Extension bridge closed');
        sent += n;
      }
    } finally {
      calloc.free(ptr);
    }
  }

  List<int> read(int fd) {
    List<int> exact(int count) {
      final ptr = calloc<Uint8>(count);
      try {
        var read = 0;
        while (read < count) {
          final n = _read(fd, ptr + read, count - read);
          if (n <= 0) throw const SocketException('Extension bridge closed');
          read += n;
        }
        return List<int>.of(ptr.asTypedList(count));
      } finally {
        calloc.free(ptr);
      }
    }

    final count = ByteData.sublistView(Uint8List.fromList(exact(4)))
        .getUint32(0);
    if (count > maxBytes)
      throw const FormatException('Extension bridge message exceeds quota');
    return exact(count);
  }
}
