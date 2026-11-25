import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:web/web.dart' as web;

enum AudioExportFormat {
  wav('wav', 'WAV'),
  mp3('mp3', 'MP3'),
  mp4('mp4', 'MP4');

  const AudioExportFormat(this.extension, this.label);
  final String extension;
  final String label;
}

enum AudioBitDepth {
  bit8(8, '8-bit PCM'),
  bit16(16, '16-bit PCM'),
  bit24(24, '24-bit PCM'),
  bit32Float(32, '32-bit Float');

  const AudioBitDepth(this.bits, this.label);
  final int bits;
  final String label;
}

/// Represents an audio track (either bundled asset or browser-selected file).
class AudioTrack {
  const AudioTrack({
    required this.name,
    required this.url,
    required this.mimeType,
    this.isObjectUrl = false,
    this.assetPath,
  });

  final String name;
  final String url;
  final String mimeType;
  final bool isObjectUrl;
  final String? assetPath;

  AudioTrack copyWith({String? url, bool? isObjectUrl}) {
    return AudioTrack(
      name: name,
      url: url ?? this.url,
      mimeType: mimeType,
      isObjectUrl: isObjectUrl ?? this.isObjectUrl,
      assetPath: assetPath,
    );
  }
}

class RemovedTrack {
  const RemovedTrack({
    required this.track,
    required this.index,
    required this.wasCurrent,
    required this.wasPlaying,
  });

  final AudioTrack track;
  final int index;
  final bool wasCurrent;
  final bool wasPlaying;
}

/// Manages HTML5 audio playback and a 3-band Web Audio API equalizer.
class WebAudioController extends ChangeNotifier {
  WebAudioController() {
    _initAudio();
    _loadBuiltInTracks();
  }

  static const List<({String title, String assetFile})> _builtInTracks = [
    (title: 'Laut aana.mp3', assetFile: 'laut_aana.mp3'),
    (title: 'Tujhe Keh Na Saka.mp3', assetFile: 'tujhe_keh_na_saka.mp3'),
    (title: 'Nazm Main Likhoon.mp3', assetFile: 'nazm_main_likhoon.mp3'),
  ];

  static const List<double> speedOptions = [
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    1.75,
    2.0,
  ];

  final web.HTMLAudioElement _audio = web.HTMLAudioElement();

  // Lazily created on the first user-initiated playback so Chrome allows it.
  web.AudioContext? _audioContext;
  web.MediaElementAudioSourceNode? _sourceNode;
  web.BiquadFilterNode? _lowFilter;
  web.BiquadFilterNode? _midFilter;
  web.BiquadFilterNode? _highFilter;

  final List<({String type, web.EventListener listener})> _audioListeners = [];
  final List<AudioTrack> _pendingRevokeTracks = [];

  List<AudioTrack> _playlist = [];
  int _currentIndex = -1;
  bool _isPlaying = false;
  bool _isSeeking = false;
  bool _isDisposed = false;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  double _lowGainDb = 0.0;
  double _midGainDb = 0.0;
  double _highGainDb = 0.0;
  double _playbackSpeed = 1.0;
  double _volume = 1.0;

  String? _statusMessage;

  List<AudioTrack> get playlist => List.unmodifiable(_playlist);
  int get currentIndex => _currentIndex;
  AudioTrack? get currentTrack =>
      (_currentIndex >= 0 && _currentIndex < _playlist.length)
          ? _playlist[_currentIndex]
          : null;

  bool get hasTracks => _playlist.isNotEmpty;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  double get lowGainDb => _lowGainDb;
  double get midGainDb => _midGainDb;
  double get highGainDb => _highGainDb;
  double get playbackSpeed => _playbackSpeed;
  double get volume => _volume;
  String? get statusMessage => _statusMessage;

  bool get hasPrevious => _playlist.isNotEmpty && _currentIndex > 0;
  bool get hasNext =>
      _playlist.isNotEmpty && _currentIndex < _playlist.length - 1;

  void _initAudio() {
    _audio.preload = 'metadata';

    void listen(String eventName, void Function(web.Event) handler) {
      final jsListener = handler.toJS;
      _audio.addEventListener(eventName, jsListener);
      _audioListeners.add((type: eventName, listener: jsListener));
    }

    listen('play', (_) {
      _isPlaying = true;
      _notifySafely();
    });

    listen('pause', (_) {
      _isPlaying = false;
      _notifySafely();
    });

    listen('loadedmetadata', (_) {
      _syncDuration();
      _notifySafely();
    });

    listen('durationchange', (_) {
      _syncDuration();
      _notifySafely();
    });

    listen('timeupdate', (_) {
      if (_isSeeking) return;
      final seconds = _audio.currentTime;
      if (seconds.isFinite && seconds >= 0) {
        _position = Duration(milliseconds: (seconds * 1000).round());
        _notifySafely();
      }
    });

    listen('ended', (_) {
      _isPlaying = false;
      if (hasNext) {
        unawaited(next());
      } else {
        _position = _duration;
        _notifySafely();
      }
    });

    listen('error', (_) {
      _isPlaying = false;
      final trackName = currentTrack?.name ?? 'this file';
      _statusMessage = 'Could not play "$trackName" (unsupported or unreadable).';
      _notifySafely();
    });
  }

  /// Creates the AudioContext and connects:
  /// audio source -> low filter -> mid filter -> high filter -> destination.
  void _ensureAudioGraph() {
    if (_audioContext != null) return;

    final ctx = web.AudioContext();
    final source = ctx.createMediaElementSource(_audio);

    final low = ctx.createBiquadFilter()
      ..type = 'lowshelf'
      ..frequency.value = 250
      ..gain.value = _lowGainDb;

    final mid = ctx.createBiquadFilter()
      ..type = 'peaking'
      ..frequency.value = 1000
      ..Q.value = 1
      ..gain.value = _midGainDb;

    final high = ctx.createBiquadFilter()
      ..type = 'highshelf'
      ..frequency.value = 4000
      ..gain.value = _highGainDb;

    // Chain the source through the three EQ filters to the speakers.
    source.connect(low);
    low.connect(mid);
    mid.connect(high);
    high.connect(ctx.destination);

    _audioContext = ctx;
    _sourceNode = source;
    _lowFilter = low;
    _midFilter = mid;
    _highFilter = high;
  }

  void _syncDuration() {
    final seconds = _audio.duration;
    if (seconds.isFinite && seconds > 0) {
      _duration = Duration(milliseconds: (seconds * 1000).round());
    } else {
      _duration = Duration.zero;
    }
  }

  /// Opens the browser's file picker to select multiple local audio files.
  Future<void> pickFiles() async {
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..multiple = true
      ..accept = 'audio/*,.mp3,.wav,.mp4,video/mp4';

    final completer = Completer<List<web.File>?>();
    late web.EventListener onChange;
    late web.EventListener onCancel;

    void cleanup() {
      input.removeEventListener('change', onChange);
      input.removeEventListener('cancel', onCancel);
    }

    onChange = ((web.Event _) {
      cleanup();
      final fileList = input.files;
      if (fileList == null || fileList.length == 0) {
        if (!completer.isCompleted) completer.complete(null);
        return;
      }
      final files = <web.File>[];
      for (var i = 0; i < fileList.length; i++) {
        final file = fileList.item(i);
        if (file != null) files.add(file);
      }
      if (!completer.isCompleted) completer.complete(files);
    }).toJS;

    onCancel = ((web.Event _) {
      cleanup();
      if (!completer.isCompleted) completer.complete(null);
    }).toJS;

    input.addEventListener('change', onChange);
    input.addEventListener('cancel', onCancel);
    input.click();

    final selectedFiles = await completer.future;
    if (_isDisposed) return;

    // User cancelled or picked nothing: keep existing playlist untouched.
    if (selectedFiles == null || selectedFiles.isEmpty) {
      return;
    }

    final validTracks = <AudioTrack>[];
    var skippedCount = 0;

    for (final file in selectedFiles) {
      final type = file.type;
      final isSupported = type.isEmpty
          ? _looksLikeAudioFileName(file.name)
          : _audio.canPlayType(type).isNotEmpty;

      if (!isSupported) {
        skippedCount++;
        continue;
      }

      final url = web.URL.createObjectURL(file);
      validTracks.add(
        AudioTrack(
          name: file.name,
          url: url,
          mimeType: type,
          isObjectUrl: true,
        ),
      );
    }

    if (validTracks.isEmpty) {
      _statusMessage = 'No supported audio files were selected.';
      _notifySafely();
      return;
    }

    final wasEmpty = _playlist.isEmpty;
    _playlist = [..._playlist, ...validTracks];
    _statusMessage = skippedCount > 0
        ? 'Skipped $skippedCount unsupported file(s).'
        : null;

    if (wasEmpty || _currentIndex < 0) {
      _currentIndex = 0;
      await _loadCurrentTrack();
      await play();
    } else {
      _notifySafely();
    }
  }

  bool _looksLikeAudioFileName(String name) {
    final lower = name.toLowerCase();
    const extensions = [
      '.mp3',
      '.wav',
      '.mp4',
      '.ogg',
      '.m4a',
      '.aac',
      '.flac',
      '.opus',
      '.webm',
    ];
    return extensions.any(lower.endsWith);
  }

  void _loadBuiltInTracks() {
    _playlist = _builtInTracks
        .map(
          (track) => AudioTrack(
            name: track.title,
            url: '',
            mimeType: 'audio/mpeg',
            assetPath: 'assets/audio/${track.assetFile}',
          ),
        )
        .toList();
    _currentIndex = 0;
    unawaited(_loadCurrentTrack());
  }

  /// Ensures bundled assets are converted to in-memory Blob URLs so Chrome
  /// supports seeking even when the dev server lacks HTTP Range support.
  Future<void> _ensureTrackUrl(int index) async {
    if (index < 0 || index >= _playlist.length) return;
    final track = _playlist[index];
    if (track.url.isNotEmpty || track.assetPath == null) return;

    final byteData = await rootBundle.load(track.assetPath!);
    if (_isDisposed) return;

    final bytes = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: track.mimeType),
    );
    final blobUrl = web.URL.createObjectURL(blob);

    if (index < _playlist.length && _playlist[index].name == track.name) {
      _playlist[index] = track.copyWith(url: blobUrl, isObjectUrl: true);
    } else {
      web.URL.revokeObjectURL(blobUrl);
    }
  }

  Future<void> _loadCurrentTrack() async {
    if (_currentIndex < 0 || _currentIndex >= _playlist.length) return;

    _position = Duration.zero;
    _duration = Duration.zero;
    _notifySafely();

    await _ensureTrackUrl(_currentIndex);
    if (_isDisposed) return;

    final track = currentTrack;
    if (track == null || track.url.isEmpty) return;

    _audio.src = track.url;
    _audio.load();
    _audio.playbackRate = _playbackSpeed;
    _notifySafely();
  }

  Future<void> selectTrack(int index) async {
    if (index < 0 || index >= _playlist.length) return;
    _statusMessage = null;
    _currentIndex = index;
    await _loadCurrentTrack();
    await play();
  }

  Future<RemovedTrack?> removeTrack(int index) async {
    if (index < 0 || index >= _playlist.length) return null;

    final wasCurrent = index == _currentIndex;
    final wasPlaying = _isPlaying;
    final removed = _playlist.removeAt(index);

    // Keep the object URL alive briefly so Undo can restore it without reloading.
    if (removed.isObjectUrl) {
      _pendingRevokeTracks.add(removed);
    }

    if (_playlist.isEmpty) {
      _stopAndResetPlayback();
      _currentIndex = -1;
      _statusMessage = null;
      _notifySafely();
    } else if (index < _currentIndex) {
      _currentIndex--;
      _notifySafely();
    } else if (wasCurrent) {
      _stopAndResetPlayback();
      if (_currentIndex >= _playlist.length) {
        _currentIndex = _playlist.length - 1;
      }
      _statusMessage = null;
      await _loadCurrentTrack();
      if (wasPlaying) {
        await play();
      }
    } else {
      _notifySafely();
    }

    return RemovedTrack(
      track: removed,
      index: index,
      wasCurrent: wasCurrent,
      wasPlaying: wasPlaying,
    );
  }

  Future<void> restoreTrack(RemovedTrack removed) async {
    _pendingRevokeTracks.remove(removed.track);

    final insertIndex = removed.index.clamp(0, _playlist.length);
    _playlist.insert(insertIndex, removed.track);

    if (removed.wasCurrent || _currentIndex == -1) {
      _currentIndex = insertIndex;
      _statusMessage = null;
      await _loadCurrentTrack();
      if (removed.wasPlaying) {
        await play();
      }
      return;
    }

    if (insertIndex <= _currentIndex) {
      _currentIndex++;
    }
    _notifySafely();
  }

  void finalizeTrackRemoval(RemovedTrack removed) {
    final wasPending = _pendingRevokeTracks.remove(removed.track);
    if (wasPending && removed.track.isObjectUrl && removed.track.url.isNotEmpty) {
      web.URL.revokeObjectURL(removed.track.url);
    }
  }

  Future<void> togglePlayPause() async {
    if (!hasTracks) return;
    if (_isPlaying) {
      pause();
    } else {
      await play();
    }
  }

  Future<void> play() async {
    if (!hasTracks) return;
    if (_currentIndex < 0) {
      _currentIndex = 0;
      await _loadCurrentTrack();
    } else if (currentTrack?.url.isEmpty ?? false) {
      await _loadCurrentTrack();
    }

    _statusMessage = null;

    try {
      // Create and resume the AudioContext inside a user-initiated action.
      _ensureAudioGraph();
      final ctx = _audioContext;
      if (ctx != null && ctx.state == 'suspended') {
        await ctx.resume().toDart;
      }
      await _audio.play().toDart;
    } catch (_) {
      _isPlaying = false;
      final trackName = currentTrack?.name ?? 'audio';
      _statusMessage = 'Unable to play "$trackName".';
      _notifySafely();
    }
  }

  void pause() {
    _audio.pause();
  }

  Future<void> previous() async {
    if (!hasPrevious) return;
    await selectTrack(_currentIndex - 1);
  }

  Future<void> next() async {
    if (!hasNext) return;
    await selectTrack(_currentIndex + 1);
  }

  void startSeeking() {
    _isSeeking = true;
  }

  void updateSeekPreview(Duration target) {
    _position = target;
    _notifySafely();
  }

  void commitSeek(Duration target) {
    _isSeeking = false;
    if (!hasTracks || _duration <= Duration.zero) return;

    final clampedMs = target.inMilliseconds.clamp(0, _duration.inMilliseconds);
    _position = Duration(milliseconds: clampedMs);
    _audio.currentTime = clampedMs / 1000.0;
    _notifySafely();
  }

  void seekBy(Duration delta) {
    if (!hasTracks || _duration <= Duration.zero) return;
    commitSeek(_position + delta);
  }

  void setPlaybackSpeed(double speed) {
    _playbackSpeed = speed.clamp(0.5, 2.0);
    _audio.playbackRate = _playbackSpeed;
    _notifySafely();
  }

  void setVolume(double value) {
    _volume = value.clamp(0.0, 1.0);
    _audio.volume = _volume;
    _notifySafely();
  }

  void setLowGain(double db) {
    _lowGainDb = db.clamp(-12.0, 12.0);
    _lowFilter?.gain.value = _lowGainDb;
    _notifySafely();
  }

  void setMidGain(double db) {
    _midGainDb = db.clamp(-12.0, 12.0);
    _midFilter?.gain.value = _midGainDb;
    _notifySafely();
  }

  void setHighGain(double db) {
    _highGainDb = db.clamp(-12.0, 12.0);
    _highFilter?.gain.value = _highGainDb;
    _notifySafely();
  }

  void resetEq() {
    _lowGainDb = 0.0;
    _midGainDb = 0.0;
    _highGainDb = 0.0;
    _lowFilter?.gain.value = 0.0;
    _midFilter?.gain.value = 0.0;
    _highFilter?.gain.value = 0.0;
    _notifySafely();
  }

  void clearError() {
    if (_statusMessage == null) return;
    _statusMessage = null;
    _notifySafely();
  }

  void _stopAndResetPlayback() {
    _audio.pause();
    _audio.removeAttribute('src');
    _audio.load();
    _isPlaying = false;
    _position = Duration.zero;
    _duration = Duration.zero;
  }

  Future<void> downloadTrack(
    int index, {
    required AudioExportFormat format,
    required AudioBitDepth bitDepth,
  }) async {
    if (index < 0 || index >= _playlist.length) return;

    await _ensureTrackUrl(index);
    if (_isDisposed || index >= _playlist.length) return;

    final track = _playlist[index];
    final dotIndex = track.name.lastIndexOf('.');
    final baseName = dotIndex > 0 ? track.name.substring(0, dotIndex) : track.name;
    final sourceExt =
        dotIndex > 0 ? track.name.substring(dotIndex + 1).toLowerCase() : '';

    if (format != AudioExportFormat.wav) {
      if (sourceExt == format.extension) {
        _triggerDownload(
          url: track.url,
          fileName: track.name,
          revokeAfter: false,
        );
        return;
      }
      _statusMessage =
          'Converting to .${format.extension} is not supported by Chrome\'s '
          'built-in Web APIs without an external encoder. Please choose WAV '
          'for format conversion and ${bitDepth.label} upscaling.';
      _notifySafely();
      return;
    }

    web.AudioContext? tempCtx;
    try {
      final response = await web.window.fetch(track.url.toJS).toDart;
      final arrayBuffer = await response.arrayBuffer().toDart;

      final ctx = _audioContext ?? (tempCtx = web.AudioContext());
      final audioBuffer = await ctx.decodeAudioData(arrayBuffer).toDart;

      final numChannels = audioBuffer.numberOfChannels;
      final sampleRate = audioBuffer.sampleRate.round();
      final channels = <Float32List>[
        for (var ch = 0; ch < numChannels; ch++)
          audioBuffer.getChannelData(ch).toDart,
      ];

      final wavBytes = _encodeWav(channels, sampleRate, bitDepth);
      final blob = web.Blob(
        [wavBytes.toJS].toJS,
        web.BlobPropertyBag(type: 'audio/wav'),
      );
      final downloadUrl = web.URL.createObjectURL(blob);
      final suffix = bitDepth == AudioBitDepth.bit32Float
          ? '32bit_float'
          : '${bitDepth.bits}bit';

      _triggerDownload(
        url: downloadUrl,
        fileName: '${baseName}_$suffix.wav',
        revokeAfter: true,
      );
    } catch (_) {
      _statusMessage = 'Could not export "${track.name}" as WAV.';
      _notifySafely();
    } finally {
      tempCtx?.close();
    }
  }

  void _triggerDownload({
    required String url,
    required String fileName,
    required bool revokeAfter,
  }) {
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = fileName
      ..style.display = 'none';
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    if (revokeAfter) {
      web.URL.revokeObjectURL(url);
    }
  }

  Uint8List _encodeWav(
    List<Float32List> channels,
    int sampleRate,
    AudioBitDepth bitDepth,
  ) {
    final numChannels = channels.length;
    final numFrames = channels.isEmpty ? 0 : channels.first.length;
    final bytesPerSample = bitDepth.bits ~/ 8;
    final blockAlign = numChannels * bytesPerSample;
    final byteRate = sampleRate * blockAlign;
    final dataSize = numFrames * blockAlign;
    final audioFormat = bitDepth == AudioBitDepth.bit32Float ? 3 : 1;

    final buffer = ByteData(44 + dataSize);

    void writeAscii(int offset, String text) {
      for (var i = 0; i < text.length; i++) {
        buffer.setUint8(offset + i, text.codeUnitAt(i));
      }
    }

    writeAscii(0, 'RIFF');
    buffer.setUint32(4, 36 + dataSize, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    buffer.setUint32(16, 16, Endian.little);
    buffer.setUint16(20, audioFormat, Endian.little);
    buffer.setUint16(22, numChannels, Endian.little);
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, byteRate, Endian.little);
    buffer.setUint16(32, blockAlign, Endian.little);
    buffer.setUint16(34, bitDepth.bits, Endian.little);
    writeAscii(36, 'data');
    buffer.setUint32(40, dataSize, Endian.little);

    var offset = 44;
    for (var i = 0; i < numFrames; i++) {
      for (var ch = 0; ch < numChannels; ch++) {
        final sample = channels[ch][i].clamp(-1.0, 1.0);
        switch (bitDepth) {
          case AudioBitDepth.bit8:
            final v = ((sample + 1.0) * 127.5).round().clamp(0, 255);
            buffer.setUint8(offset, v);
            offset += 1;
          case AudioBitDepth.bit16:
            final v = (sample * 32767.0).round().clamp(-32768, 32767);
            buffer.setInt16(offset, v, Endian.little);
            offset += 2;
          case AudioBitDepth.bit24:
            final v = (sample * 8388607.0).round().clamp(-8388608, 8388607);
            buffer.setUint8(offset, v & 0xFF);
            buffer.setUint8(offset + 1, (v >> 8) & 0xFF);
            buffer.setUint8(offset + 2, (v >> 16) & 0xFF);
            offset += 3;
          case AudioBitDepth.bit32Float:
            buffer.setFloat32(offset, sample, Endian.little);
            offset += 4;
        }
      }
    }

    return buffer.buffer.asUint8List();
  }

  void _revokePlaylistUrls() {
    for (final track in _playlist) {
      if (track.isObjectUrl && track.url.isNotEmpty) {
        web.URL.revokeObjectURL(track.url);
      }
    }
    for (final track in _pendingRevokeTracks) {
      if (track.isObjectUrl && track.url.isNotEmpty) {
        web.URL.revokeObjectURL(track.url);
      }
    }
    _pendingRevokeTracks.clear();
    _playlist = [];
    _currentIndex = -1;
  }

  void _notifySafely() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _stopAndResetPlayback();
    _revokePlaylistUrls();

    for (final entry in _audioListeners) {
      _audio.removeEventListener(entry.type, entry.listener);
    }
    _audioListeners.clear();

    _sourceNode?.disconnect();
    _lowFilter?.disconnect();
    _midFilter?.disconnect();
    _highFilter?.disconnect();
    _audioContext?.close();

    _sourceNode = null;
    _lowFilter = null;
    _midFilter = null;
    _highFilter = null;
    _audioContext = null;

    super.dispose();
  }
}
