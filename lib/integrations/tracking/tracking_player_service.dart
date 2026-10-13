// Foxfin: forwards playback events to Trakt/Simkl scrobbling.
// GPL-2.0-or-later, see NOTICE.
import 'dart:async';

import 'package:playback_core/playback_core.dart';

import 'tracker.dart';
import 'tracking_service.dart';

class TrackingPlayerService implements PlayerService {
  final PlayerService _inner;
  final TrackingService _tracking;
  final Map<String, bool> _paused = {};

  TrackingPlayerService(this._inner, this._tracking);

  String? _id(dynamic mediaItem) {
    try {
      return MediaStreamResolver.extractItemId(mediaItem);
    } catch (_) {
      return null;
    }
  }

  void _emit(ScrobbleAction a, dynamic mediaItem, Duration pos) {
    final id = _id(mediaItem);
    if (id == null) return;
    unawaited(_tracking.onPlayback(a, id, pos));
  }

  @override
  Future<void> onPlaybackStart(dynamic mediaItem, StreamResolutionResult resolution,
      {int? positionTicks, int? audioStreamIndex, int? subtitleStreamIndex}) {
    final id = _id(mediaItem);
    if (id != null) _paused[id] = false;
    _emit(ScrobbleAction.start, mediaItem,
        Duration(microseconds: (positionTicks ?? 0) ~/ 10));
    return _inner.onPlaybackStart(mediaItem, resolution,
        positionTicks: positionTicks,
        audioStreamIndex: audioStreamIndex,
        subtitleStreamIndex: subtitleStreamIndex);
  }

  @override
  Future<void> onPlaybackProgress(dynamic mediaItem,
      StreamResolutionResult resolution, Duration position,
      {bool isPaused = false,
      int? audioStreamIndex,
      int? subtitleStreamIndex,
      int? volumeLevel,
      bool? isMuted}) {
    final id = _id(mediaItem);
    if (id != null && _paused[id] != isPaused) {
      _paused[id] = isPaused;
      _emit(isPaused ? ScrobbleAction.pause : ScrobbleAction.start, mediaItem,
          position);
    }
    return _inner.onPlaybackProgress(mediaItem, resolution, position,
        isPaused: isPaused,
        audioStreamIndex: audioStreamIndex,
        subtitleStreamIndex: subtitleStreamIndex,
        volumeLevel: volumeLevel,
        isMuted: isMuted);
  }

  @override
  Future<void> onPlaybackStop(dynamic mediaItem,
      StreamResolutionResult resolution, Duration position,
      {bool releaseLiveStream = true}) {
    final id = _id(mediaItem);
    if (id != null) _paused.remove(id);
    _emit(ScrobbleAction.stop, mediaItem, position);
    return _inner.onPlaybackStop(mediaItem, resolution, position,
        releaseLiveStream: releaseLiveStream);
  }

  @override
  Future<void> closeLiveStream(String liveStreamId) =>
      _inner.closeLiveStream(liveStreamId);

  @override
  Future<void> stopTranscoding(StreamResolutionResult resolution) =>
      _inner.stopTranscoding(resolution);

  @override
  void dispose() => _inner.dispose();
}
