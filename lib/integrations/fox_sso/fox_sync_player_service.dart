// Foxfin: reports pause/stop positions of shop-server items to the FOX account.
// GPL-2.0-or-later, see NOTICE.
import 'dart:async';

import 'package:playback_core/playback_core.dart';

import 'fox_sync_service.dart';

class FoxSyncPlayerService implements PlayerService {
  final PlayerService _inner;
  final Map<String, bool> _paused = {};
  FoxSyncPlayerService(this._inner);

  String? _id(dynamic m) {
    try {
      return MediaStreamResolver.extractItemId(m);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> onPlaybackStart(dynamic mediaItem, StreamResolutionResult resolution,
          {int? positionTicks, int? audioStreamIndex, int? subtitleStreamIndex}) =>
      _inner.onPlaybackStart(mediaItem, resolution,
          positionTicks: positionTicks,
          audioStreamIndex: audioStreamIndex,
          subtitleStreamIndex: subtitleStreamIndex);

  @override
  Future<void> onPlaybackProgress(dynamic mediaItem,
      StreamResolutionResult resolution, Duration position,
      {bool isPaused = false,
      int? audioStreamIndex,
      int? subtitleStreamIndex,
      int? volumeLevel,
      bool? isMuted}) {
    final id = _id(mediaItem);
    if (id != null && !resolution.isLocalMedia && (_paused[id] ?? false) != isPaused) {
      _paused[id] = isPaused;
      if (isPaused) unawaited(FoxSyncService.instance.reportProgress(id, position));
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
    if (id != null) {
      _paused.remove(id);
      if (!resolution.isLocalMedia) {
        // Give the server a moment to record the stop/played state first.
        unawaited(Future<void>.delayed(const Duration(seconds: 3), () =>
            FoxSyncService.instance.reportProgress(id, position, stopped: true)));
      }
    }
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
