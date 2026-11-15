import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter_qjs_next/flutter_qjs.dart';
import 'package:http/http.dart' as http;
import 'package:yazhal/services/extensions/extension_package.dart';
import 'package:yazhal/services/extensions/extension_rpc_socket.dart';
import 'package:yazhal/services/public_network_client.dart';
import 'package:yazhal/services/source_diagnostics.dart';

class ExtensionRunResult {
  ExtensionRunResult(this.value, this.storage);
  final dynamic value;
  final Map<String, dynamic> storage;
}

/// Real QuickJS execution, preserving Mornye's synchronous SDK contract without
/// rewriting provider JavaScript. Native VM lives exclusively on a worker isolate.
class ExtensionRuntime {
  ExtensionRuntime({http.Client? client, this.jsTimeoutMillis = 30000})
    : client = client ?? PublicNetworkClient.create();
  final int jsTimeoutMillis;
  static int _active = 0;
  static final _waiting = Queue<Completer<void>>();
  static Future<void> _acquire() async {
    if (_active < 2) {
      _active++;
      return;
    }
    if (_waiting.length >= 16)
      throw StateError('Too many pending extension requests');
    final waiter = Completer<void>();
    _waiting.add(waiter);
    await waiter.future;
  }

  static void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete();
    } else {
      _active--;
    }
  }

  final http.Client client;
  Future<ExtensionRunResult> call(
    ExtensionPackage package,
    String method,
    List args, {
    Map<String, dynamic> settings = const {},
    Map<String, dynamic> storage = const {},
  }) async {
    await _acquire();
    try {
      return await _run(
        package,
        method,
        args,
        settings: settings,
        storage: storage,
      );
    } finally {
      _release();
    }
  }

  Future<ExtensionRunResult> _run(
    ExtensionPackage package,
    String method,
    List args, {
    Map<String, dynamic> settings = const {},
    Map<String, dynamic> storage = const {},
  }) async {
    final socket = ExtensionRpcSocket();
    final fds = socket.create();
    final messages = ReceivePort();
    final result = Completer<ExtensionRunResult>();
    var closed = false, requests = 0;
    Isolate? worker;
    Future<void> receive(dynamic event) async {
      if (closed) return;
      if (event is! Map) {
        if (!result.isCompleted)
          result.completeError(StateError('Extension worker failed'));
        return;
      }
      if (event['type'] == 'rpc') {
        Map response;
        try {
          if (++requests > 24)
            throw const FormatException('Extension request quota exceeded');
          response = {
            'value': await _host(
              package,
              event['op'].toString(),
              event['args'] as List? ?? [],
            ),
          };
        } catch (e) {
          response = {
            'error': e is FormatException ? e.message : safeNetworkFailure(e),
          };
        }
        if (!closed) {
          try {
            socket.write(fds[0], utf8.encode(jsonEncode(response)));
          } catch (e) {
            if (!result.isCompleted) result.completeError(e);
          }
        }
      } else if (event['type'] == 'done' && !result.isCompleted) {
        if (event['error'] != null)
          result.completeError(StateError(event['error'].toString()));
        else
          result.complete(
            ExtensionRunResult(
              event['value'],
              Map<String, dynamic>.from(event['storage'] as Map? ?? {}),
            ),
          );
      }
    }

    final subscription = messages.listen((event) => unawaited(receive(event)));
    try {
      worker = await Isolate.spawn(_extensionWorker, {
        'port': messages.sendPort,
        'fd': fds[1],
        'source': package.source,
        'method': method,
        'args': args,
        'settings': settings,
        'storage': storage,
        'timeout': jsTimeoutMillis,
      }, onError: messages.sendPort);
      return await result.future.timeout(const Duration(seconds: 45));
    } finally {
      closed = true;
      socket.stop(fds[0]);
      worker?.kill();
      await subscription.cancel();
      messages.close();
      socket.close(fds[0]);
      if (worker == null) socket.close(fds[1]);
    }
  }

  Future<dynamic> _host(ExtensionPackage package, String op, List args) async {
    if (op == 'sleep') {
      final ms = (args.first as num).toInt().clamp(0, 500);
      await Future<void>.delayed(Duration(milliseconds: ms));
      return true;
    }
    if (op != 'http')
      throw const FormatException('Unsupported extension host API');
    final method = args[0].toString().toUpperCase();
    if (!{'GET', 'POST', 'HEAD'}.contains(method))
      throw const FormatException('HTTP method is not supported');
    var uri = Uri.parse(args[1].toString());
    final headers =
        Map<String, String>.from(
          (args[2] as Map? ?? {}).map(
            (k, v) => MapEntry(k.toString(), v.toString()),
          ),
        )..removeWhere(
          (k, v) =>
              {
                'host',
                'content-length',
                'connection',
                'proxy-authorization',
              }.contains(k.toLowerCase()) ||
              v.contains('\r') ||
              v.contains('\n'),
        );
    final body = args.length > 3 ? args[3]?.toString() : null;
    if (body != null && utf8.encode(body).length > 1024 * 1024)
      throw const FormatException('Request body too large');
    var requestMethod = method;
    for (var redirects = 0; redirects <= 5; redirects++) {
      if (!package.allows(uri))
        throw const FormatException(
          'Extension request outside declared public HTTPS hosts',
        );
      final request = http.Request(requestMethod, uri)..followRedirects = false;
      request.headers.addAll(headers);
      if (body != null && requestMethod == 'POST') request.body = body;
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 15));
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        final next = response.headers['location'];
        await PublicNetworkClient.cancelBody(response);
        if (next == null)
          throw const FormatException('Redirect has no location');
        final target = uri.resolve(next);
        if (target.host != uri.host)
          headers.removeWhere(
            (k, v) => RegExp(
              'authorization|cookie|token|api.?key',
              caseSensitive: false,
            ).hasMatch(k),
          );
        if (response.statusCode == 303 ||
            ((response.statusCode == 301 || response.statusCode == 302) &&
                requestMethod == 'POST'))
          requestMethod = 'GET';
        uri = target;
        continue;
      }
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 15),
      )) {
        if (bytes.length + chunk.length > 2 * 1024 * 1024)
          throw const FormatException('Extension HTTP response exceeds 2 MiB');
        bytes.addAll(chunk);
      }
      if (package.id == 'jiosaavn' && uri.path == '/api.php') {
        final problem = jioResponseProblem(
          response.statusCode,
          response.headers['content-type'],
          utf8.decode(bytes, allowMalformed: true),
          searchResponse: uri.queryParameters['__call'] == 'search.getResults',
        );
        if (problem != null) throw FormatException(problem);
      }
      return {
        'statusCode': response.statusCode,
        'status': response.statusCode,
        'ok': response.statusCode >= 200 && response.statusCode < 300,
        'body': utf8.decode(bytes, allowMalformed: true),
        'headers': response.headers,
        'url': uri.toString(),
      };
    }
    throw const FormatException('Too many extension redirects');
  }

  void close() => client.close();
}

void _extensionWorker(Map input) {
  final port = input['port'] as SendPort;
  final socket = ExtensionRpcSocket();
  JavascriptRuntime? js;
  Map output;
  try {
    js = getJavascriptRuntime(timeout: input['timeout'] as int? ?? 30000)
      ..onMessage('__yazhal_host', (dynamic message) {
        final values = message as List;
        final op = values[0].toString();
        final args = values[1] as List;
        if (op == 'md5')
          return jsonEncode({
            'value': md5.convert(utf8.encode(args[0].toString())).toString(),
          });
        if (op == 'sha256')
          return jsonEncode({
            'value': sha256.convert(utf8.encode(args[0].toString())).toString(),
          });
        port.send({'type': 'rpc', 'op': op, 'args': args});
        return utf8.decode(socket.read(input['fd'] as int));
      });
    final setup = js.evaluate(_sdkBootstrap);
    if (setup.isError) throw StateError(setup.stringResult);
    final source = js.evaluate(input['source'] as String);
    if (source.isError)
      throw StateError('Extension failed to load: ${source.stringResult}');
    final payload = jsonEncode({
      'method': input['method'],
      'args': input['args'],
      'settings': input['settings'],
      'storage': input['storage'],
    });
    final response = js.evaluate('JSON.stringify(__yazhalInvoke($payload))');
    if (response.isError) throw StateError(response.stringResult);
    if (utf8.encode(response.stringResult).length > 4 * 1024 * 1024)
      throw const FormatException('Extension result exceeds quota');
    final decoded = jsonDecode(response.stringResult) as Map;
    output = {'type': 'done', ...decoded};
  } catch (e) {
    output = {'type': 'done', 'error': e.toString()};
  } finally {
    try {
      js?.dispose();
    } finally {
      socket.close(input['fd'] as int);
    }
  }
  port.send(output);
}

const _sdkBootstrap = r'''
var __provider = null, __store = Object.create(null);
console={log:function(){},info:function(){},warn:function(){},error:function(){},debug:function(){}};
globalThis.setTimeout=globalThis.setInterval=function(){throw new Error('Timers are not supported in synchronous provider calls');};
function registerExtension(provider) { if (__provider) throw new Error('Only one provider per package'); __provider=provider; }
function __host(op,args) { var r=JSON.parse(sendMessage('__yazhal_host',JSON.stringify([op,args]))); if(r.error)throw new Error(r.error);return r.value; }
var log={debug:function(){},info:function(){},warn:function(){},error:function(){}};
var storage={get:function(k,fallback){return Object.prototype.hasOwnProperty.call(__store,k)?__store[k]:fallback;},set:function(k,v){if(String(k).length>256)throw new Error('Storage key too long');__store[k]=v;if(JSON.stringify(__store).length>524288)throw new Error('Storage quota exceeded');return true;},remove:function(k){delete __store[k];return true;},clear:function(){__store=Object.create(null);return true;}};
var http={get:function(url,headers){return __host('http',['GET',url,headers||{}]);},post:function(url,body,headers){return __host('http',['POST',url,headers||{},body]);},head:function(url,headers){return __host('http',['HEAD',url,headers||{}]);}};
var utils={md5:function(s){return __host('md5',[s]);},sha256:function(s){return __host('sha256',[s]);},sleep:function(ms){return __host('sleep',[ms]);},randomUserAgent:function(){return 'Mozilla/5.0';},appUserAgent:function(){return 'Yazhal';},isDownloadCancelled:function(){return false;},isRequestCancelled:function(){return false;}};
var file=new Proxy({}, {get:function(){return function(){throw new Error('This file API is not supported. Yazhal downloads validated direct URLs through its own storage manager.');};}});
var gobackend={sanitizeFilename:function(s){return String(s).replace(/[\\/:*?"<>|]/g,'_');}};
var matching={normalizeString:function(s){return String(s||'').normalize('NFKD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/[^\p{L}\p{N}\s]/gu,' ').replace(/\s+/g,' ').trim();},compareStrings:function(a,b){a=this.normalizeString(a).slice(0,256);b=this.normalizeString(b).slice(0,256);if(a===b)return 1;if(!a||!b)return 0;var previous=Array.from({length:b.length+1},function(_,i){return i;});for(var i=1;i<=a.length;i++){var next=[i];for(var j=1;j<=b.length;j++)next[j]=Math.min(next[j-1]+1,previous[j]+1,previous[j-1]+(a[i-1]===b[j-1]?0:1));previous=next;}return 1-previous[b.length]/Math.max(a.length,b.length);},compareDuration:function(a,b){a=Number(a)||0;b=Number(b)||0;return a>0&&b>0?Math.max(0,1-Math.abs(a-b)/Math.max(a,b)):0;}};
function __yazhalInvoke(input) {
  __store=input.storage||Object.create(null);
  if(!__provider)throw new Error('Package did not register a provider');
  if(typeof __provider.initialize==='function')__provider.initialize(input.settings||{});
  if(input.method==='__inspect')return {value:Object.keys(__provider).filter(function(k){return typeof __provider[k]==='function';}),storage:__store};
  if(typeof __provider[input.method]!=='function')throw new Error('Provider does not support '+input.method);
  var value=__provider[input.method].apply(null,input.args||[]);
  if(value && typeof value.then==='function')throw new Error('Async provider callbacks require an additional runtime adapter');
  return {value:value===undefined?null:value,storage:__store};
}
''';
