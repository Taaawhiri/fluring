import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

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

  static const _signallingHost =
      'api.prod.signalling.ring.devices.a2z.com';

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
      onTimeout: () => throw const RingException(
        'The camera did not answer in time',
      ),
    );
  }

  Future<void> _start() async {
    await _renderer.initialize();
    await _openSocket();
    await _openPeer();
    await _sendOffer();
    await _connected.future;
  }

  Future<void> _openSocket() async {
    final token = await _auth.accessToken();
    final uri = Uri(
      scheme: 'wss',
      host: _signallingHost,
      path: '/ws',
      queryParameters: {
        'api_version': '4.0',
        'auth_type': 'ring_solutions',
        'client_id': 'ring_site-${_randomUuid()}',
        'token': token,
      },
    );

    final socket = WebSocketChannel.connect(uri);
    await socket.ready;
    _socket = socket;
    _messages = socket.stream.listen(
      _onMessage,
      onError: (Object error) => _fail(RingException('Signalling error: $error')),
      onDone: () => _fail(const RingException('Ring closed the connection')),
    );
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

    switch (message['method']) {
      case 'sdp':
        final sdp = fields['sdp'];
        if (sdp is String) {
          await _peer?.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
        }
      case 'ice':
        final ice = fields['ice'];
        if (ice is String) {
          await _peer?.addCandidate(RTCIceCandidate(
            ice,
            null,
            (fields['mlineindex'] as num?)?.toInt() ?? 0,
          ));
        }
      case 'close':
        _fail(RingException(_closeReason(fields)));
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
