import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../diagnostics/diagnostic_log.dart';

import 'ring_auth.dart';
import 'ring_exceptions.dart';

/// How far a live view runs before Ring drops it on its own.
///
/// Ring tears a session down after a few minutes regardless; we keep the
/// session alive with pings and let the UI decide whether to reconnect.
const _pingInterval = Duration(seconds: 5);

/// A single WebRTC live view of one camera.
///
/// Ring's signalling is a WebSocket exchanging JSON envelopes: we send an SDP
/// offer inside a `live_view` message, Ring answers with `sdp`, and both sides
/// trickle ICE candidates. Everything is torn down through [dispose] — a leaked
/// peer connection keeps the camera awake and drains its battery.
class RingLiveStream {
  RingLiveStream({required RingAuth auth, required this.cameraId})
    : _auth = auth; // ignore: prefer_initializing_formals

  static const _signallingHost = 'api.prod.signalling.ring.devices.a2z.com';

  /// Where the short-lived signalling ticket comes from. This is a separate
  /// host from the rest of the Ring API (`api.ring.com`) — easy to miss, and
  /// missing it is exactly what left the socket connect hanging forever: the
  /// signalling server expects this ticket as its `token` parameter, not the
  /// account's own OAuth access token.
  static const _ticketUrl =
      'https://prd-api-us.prd.rings.solutions/api/v1/clap/ticket/request/signalsocket';

  final RingAuth _auth;
  final int cameraId;

  final _dialogId = _randomUuid();
  final _renderer = RTCVideoRenderer();
  final _connected = Completer<void>();

  WebSocketChannel? _socket;
  RTCPeerConnection? _peer;
  Timer? _ping;
  StreamSubscription<dynamic>? _messages;
  bool _disposed = false;

  /// Renders the remote track once [start] resolves.
  RTCVideoRenderer get renderer => _renderer;

  /// Opens the stream, completing when the first remote track arrives.
  ///
  /// Throws [RingException] if signalling fails or the camera never answers.
  Future<void> start({Duration timeout = const Duration(seconds: 30)}) {
    // The whole sequence is bounded, not just the final handshake wait: an
    // unreachable signalling host can hang the WebSocket connect step itself
    // indefinitely, well before there is a connected socket to time out on.
    // Without this, that case span forever with a spinner and no error.
    return _start().timeout(
      timeout,
      onTimeout: () =>
          throw const RingException('The camera did not answer in time'),
    );
  }

  Future<void> _start() async {
    DiagnosticLog.add('live[$cameraId]: starting');
    await _renderer.initialize();
    await _openSocket();
    await _openPeer();
    await _sendOffer();
    await _connected.future;
    DiagnosticLog.add('live[$cameraId]: track received, connected');
  }

  Future<void> _openSocket() async {
    DiagnosticLog.add('live[$cameraId]: requesting signalling ticket');
    final ticket = await _requestSignallingTicket();
    DiagnosticLog.add('live[$cameraId]: got ticket, opening signalling socket');
    final uri = Uri(
      scheme: 'wss',
      host: _signallingHost,
      path: '/ws',
      queryParameters: {
        'api_version': '4.0',
        'auth_type': 'ring_solutions',
        'client_id': 'ring_site-${_randomUuid()}',
        'token': ticket,
      },
    );

    final socket = WebSocketChannel.connect(uri);
    await socket.ready;
    DiagnosticLog.add('live[$cameraId]: signalling socket open');
    _socket = socket;
    _messages = socket.stream.listen(
      _onMessage,
      onError: (Object error) {
        DiagnosticLog.add('live[$cameraId]: socket error: $error');
        _fail(RingException('Signalling error: $error'));
      },
      onDone: () {
        DiagnosticLog.add('live[$cameraId]: socket closed by peer');
        _fail(const RingException('Ring closed the connection'));
      },
    );
  }

  /// Fetches the one-time ticket the signalling server requires.
  ///
  /// Same auth headers as every other Ring API call, but a different host
  /// entirely from `api.ring.com` — the two are easy to conflate since
  /// nothing about the ticket endpoint's name suggests it lives elsewhere.
  Future<String> _requestSignallingTicket() async {
    final headers = await _auth.authHeaders();
    final response = await http.post(Uri.parse(_ticketUrl), headers: headers);

    if (response.statusCode == 401) {
      throw const RingSessionExpired();
    }
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw RingException(
        'Could not get a signalling ticket (HTTP ${response.statusCode})',
      );
    }

    final body = jsonDecode(response.body);
    final ticket = body is Map<String, dynamic> ? body['ticket'] : null;
    if (ticket is! String) {
      throw const RingException('Ring did not return a signalling ticket');
    }
    return ticket;
  }

  Future<void> _openPeer() async {
    final peer = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    });

    // Ring only sends; declaring both transceivers as recvonly keeps the offer
    // shaped the way its backend expects.
    await peer.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
    );
    await peer.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
    );

    peer.onTrack = (RTCTrackEvent event) {
      if (event.streams.isEmpty) return;
      _renderer.srcObject = event.streams.first;
      if (!_connected.isCompleted) _connected.complete();
    };

    peer.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate == null) return;
      _send({
        'method': 'ice',
        'dialog_id': _dialogId,
        'body': {
          'doorbot_id': cameraId,
          'ice': candidate.candidate,
          'mlineindex': candidate.sdpMLineIndex ?? 0,
        },
      });
    };

    peer.onConnectionState = (RTCPeerConnectionState state) {
      DiagnosticLog.add('live[$cameraId]: peer connection state -> $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _fail(const RingException('Video connection failed'));
      }
    };

    _peer = peer;
  }

  Future<void> _sendOffer() async {
    final peer = _peer!;
    final offer = await peer.createOffer();
    await peer.setLocalDescription(offer);
    DiagnosticLog.add('live[$cameraId]: sending offer via live_view');

    _send({
      'method': 'live_view',
      'dialog_id': _dialogId,
      'body': {
        'doorbot_id': cameraId,
        'stream_options': {'audio_enabled': true, 'video_enabled': true},
        'sdp': offer.sdp,
      },
    });

    _ping = Timer.periodic(_pingInterval, (_) {
      _send({
        'method': 'ping',
        'dialog_id': _dialogId,
        'body': {'doorbot_id': cameraId},
      });
    });
  }

  Future<void> _onMessage(dynamic raw) async {
    if (raw is! String) return;

    final Map<String, dynamic> message;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      message = decoded;
    } on FormatException {
      return;
    }

    final body = message['body'];
    final fields = body is Map<String, dynamic> ? body : const {};

    DiagnosticLog.add("live[$cameraId]: received '${message['method']}'");
    switch (message['method']) {
      case 'sdp':
        final sdp = fields['sdp'];
        if (sdp is String) {
          await _peer?.setRemoteDescription(
            RTCSessionDescription(sdp, 'answer'),
          );
          DiagnosticLog.add('live[$cameraId]: remote SDP applied');
        }
      case 'ice':
        final ice = fields['ice'];
        if (ice is String) {
          await _peer?.addCandidate(
            RTCIceCandidate(
              ice,
              null,
              (fields['mlineindex'] as num?)?.toInt() ?? 0,
            ),
          );
        }
      case 'close':
        final reason = _closeReason(fields);
        DiagnosticLog.add('live[$cameraId]: close received: $reason');
        _fail(RingException(reason));
    }
  }

  String _closeReason(Map<Object?, Object?> body) {
    final reason = body['reason'];
    if (reason is Map && reason['text'] is String) {
      final text = reason['text'] as String;
      if (text.isNotEmpty) return 'Ring ended the stream: $text';
    }
    return 'Ring ended the stream';
  }

  void _fail(RingException error) {
    DiagnosticLog.add('live[$cameraId]: failing with: ${error.message}');
    if (!_connected.isCompleted) _connected.completeError(error);
  }

  void _send(Map<String, dynamic> message) {
    if (_disposed) return;
    _socket?.sink.add(jsonEncode(message));
  }

  /// Releases the camera. Safe to call more than once.
  Future<void> dispose() async {
    if (_disposed) return;

    _ping?.cancel();
    // Tell Ring to release the camera before we shut the socket, otherwise the
    // device stays awake until the server times the session out.
    _send({
      'method': 'close',
      'dialog_id': _dialogId,
      'body': {
        'doorbot_id': cameraId,
        'reason': {'code': 0, 'text': ''},
      },
    });
    _disposed = true;

    await _messages?.cancel();
    await _socket?.sink.close();
    await _peer?.close();
    _renderer.srcObject = null;
    await _renderer.dispose();
  }
}

String _randomUuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
