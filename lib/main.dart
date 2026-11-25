import 'dart:async';

import 'package:flutter/material.dart';

import 'web_audio_controller.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Music EQ Player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const MusicPlayerScreen(),
    );
  }
}

class MusicPlayerScreen extends StatefulWidget {
  const MusicPlayerScreen({super.key});

  @override
  State<MusicPlayerScreen> createState() => _MusicPlayerScreenState();
}

class _MusicPlayerScreenState extends State<MusicPlayerScreen> {
  final WebAudioController _controller = WebAudioController();
  Timer? _undoTimer;

  @override
  void dispose() {
    _undoTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$mm:$ss';
    }
    return '$mm:$ss';
  }

  Future<void> _handleRemoveTrack(int index) async {
    final removed = await _controller.removeTrack(index);
    if (removed == null || !mounted) return;

    _undoTimer?.cancel();
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final controller = messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        content: Text('Removed "${removed.track.name}"'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            _undoTimer?.cancel();
            _controller.restoreTrack(removed);
          },
        ),
      ),
    );

    _undoTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        controller.close();
      }
    });

    final reason = await controller.closed;
    _undoTimer?.cancel();
    if (reason != SnackBarClosedReason.action) {
      _controller.finalizeTrackRemoval(removed);
    }
  }

  Future<void> _showDownloadDialog(int index, AudioTrack track) async {
    var selectedFormat = AudioExportFormat.wav;
    var selectedBitDepth = AudioBitDepth.bit24;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Download Audio'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.name,
                    style: Theme.of(context).textTheme.bodyMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<AudioExportFormat>(
                    initialValue: selectedFormat,
                    decoration: const InputDecoration(
                      labelText: 'Format',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final format in AudioExportFormat.values)
                        DropdownMenuItem(
                          value: format,
                          child: Text('.${format.extension} (${format.label})'),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => selectedFormat = value);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<AudioBitDepth>(
                    initialValue: selectedBitDepth,
                    decoration: const InputDecoration(
                      labelText: 'Resolution (WAV PCM)',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final depth in AudioBitDepth.values)
                        DropdownMenuItem(
                          value: depth,
                          child: Text(depth.label),
                        ),
                    ],
                    onChanged: selectedFormat == AudioExportFormat.wav
                        ? (value) {
                            if (value != null) {
                              setDialogState(() => selectedBitDepth = value);
                            }
                          }
                        : null,
                  ),
                  if (selectedFormat != AudioExportFormat.wav) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Bit-depth PCM upscaling (8/16/24/32-bit) applies to WAV. '
                      'MP3/MP4 downloads are only available when the source '
                      'file is already in that format.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    _controller.downloadTrack(
                      index,
                      format: selectedFormat,
                      bitDepth: selectedBitDepth,
                    );
                  },
                  icon: const Icon(Icons.download),
                  label: const Text('Download'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Music EQ Player'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: _controller.pickFiles,
              icon: const Icon(Icons.folder_open),
              label: const Text('Select Audio Files'),
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final currentTrack = _controller.currentTrack;
          final durationMs = _controller.duration.inMilliseconds;
          final positionMs = _controller.position.inMilliseconds;
          final maxMs = durationMs > 0 ? durationMs.toDouble() : 1.0;
          final sliderValue = positionMs.toDouble().clamp(0.0, maxMs);

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (_controller.statusMessage != null)
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      margin: const EdgeInsets.only(bottom: 16),
                      child: ListTile(
                        leading: Icon(
                          Icons.warning_amber_rounded,
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                        title: Text(
                          _controller.statusMessage!,
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onErrorContainer,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          color: Theme.of(context).colorScheme.onErrorContainer,
                          onPressed: _controller.clearError,
                        ),
                      ),
                    ),

                  // Now Playing & Transport Controls
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Now Playing',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            currentTrack?.name ?? 'No track selected',
                            style: Theme.of(context).textTheme.titleLarge,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 16),
                          Slider(
                            value: sliderValue,
                            min: 0.0,
                            max: maxMs,
                            onChangeStart:
                                _controller.hasTracks && durationMs > 0
                                    ? (_) => _controller.startSeeking()
                                    : null,
                            onChanged: _controller.hasTracks && durationMs > 0
                                ? (value) => _controller.updateSeekPreview(
                                      Duration(milliseconds: value.round()),
                                    )
                                : null,
                            onChangeEnd: _controller.hasTracks && durationMs > 0
                                ? (value) => _controller.commitSeek(
                                      Duration(milliseconds: value.round()),
                                    )
                                : null,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_formatDuration(_controller.position)),
                                Text(_formatDuration(_controller.duration)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton.filledTonal(
                                iconSize: 28,
                                tooltip: 'Back 5 seconds',
                                onPressed:
                                    _controller.hasTracks && durationMs > 0
                                        ? () => _controller.seekBy(
                                              const Duration(seconds: -5),
                                            )
                                        : null,
                                icon: const Icon(Icons.replay_5),
                              ),
                              const SizedBox(width: 12),
                              IconButton.filledTonal(
                                iconSize: 32,
                                tooltip: 'Previous',
                                onPressed: _controller.hasPrevious
                                    ? _controller.previous
                                    : null,
                                icon: const Icon(Icons.skip_previous),
                              ),
                              const SizedBox(width: 16),
                              IconButton.filled(
                                iconSize: 40,
                                tooltip:
                                    _controller.isPlaying ? 'Pause' : 'Play',
                                onPressed: _controller.hasTracks
                                    ? _controller.togglePlayPause
                                    : null,
                                icon: Icon(
                                  _controller.isPlaying
                                      ? Icons.pause
                                      : Icons.play_arrow,
                                ),
                              ),
                              const SizedBox(width: 16),
                              IconButton.filledTonal(
                                iconSize: 32,
                                tooltip: 'Next',
                                onPressed:
                                    _controller.hasNext ? _controller.next : null,
                                icon: const Icon(Icons.skip_next),
                              ),
                              const SizedBox(width: 12),
                              IconButton.filledTonal(
                                iconSize: 28,
                                tooltip: 'Forward 5 seconds',
                                onPressed:
                                    _controller.hasTracks && durationMs > 0
                                        ? () => _controller.seekBy(
                                              const Duration(seconds: 5),
                                            )
                                        : null,
                                icon: const Icon(Icons.forward_5),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              Text(
                                'Speed:',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              for (final speed
                                  in WebAudioController.speedOptions)
                                ChoiceChip(
                                  label: Text('${speed}x'),
                                  selected: _controller.playbackSpeed == speed,
                                  onSelected: _controller.hasTracks
                                      ? (_) =>
                                          _controller.setPlaybackSpeed(speed)
                                      : null,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Volume
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _controller.volume == 0
                                ? Icons.volume_off
                                : _controller.volume < 0.5
                                    ? Icons.volume_down
                                    : Icons.volume_up,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Volume',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Expanded(
                            child: Slider(
                              value: _controller.volume,
                              min: 0.0,
                              max: 1.0,
                              divisions: 20,
                              label: '${(_controller.volume * 100).round()}%',
                              onChanged: _controller.setVolume,
                            ),
                          ),
                          SizedBox(
                            width: 48,
                            child: Text(
                              '${(_controller.volume * 100).round()}%',
                              textAlign: TextAlign.end,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 3-Band Equalizer
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Equalizer',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              OutlinedButton.icon(
                                onPressed: _controller.resetEq,
                                icon: const Icon(Icons.refresh, size: 18),
                                label: const Text('Reset EQ'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _EqSliderRow(
                            label: 'Low',
                            subtitle: '250 Hz',
                            gainDb: _controller.lowGainDb,
                            onChanged: _controller.setLowGain,
                          ),
                          _EqSliderRow(
                            label: 'Mid',
                            subtitle: '1000 Hz',
                            gainDb: _controller.midGainDb,
                            onChanged: _controller.setMidGain,
                          ),
                          _EqSliderRow(
                            label: 'High',
                            subtitle: '4000 Hz',
                            gainDb: _controller.highGainDb,
                            onChanged: _controller.setHighGain,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Playlist
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Playlist (${_controller.playlist.length})',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          if (!_controller.hasTracks)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              child: Column(
                                children: [
                                  const Icon(Icons.library_music, size: 40),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'No audio files loaded yet.',
                                  ),
                                  const SizedBox(height: 12),
                                  ElevatedButton.icon(
                                    onPressed: _controller.pickFiles,
                                    icon: const Icon(Icons.folder_open),
                                    label: const Text('Choose Audio Files'),
                                  ),
                                ],
                              ),
                            )
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _controller.playlist.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final track = _controller.playlist[index];
                                final isCurrent =
                                    index == _controller.currentIndex;

                                return ListTile(
                                  selected: isCurrent,
                                  leading: Icon(
                                    isCurrent && _controller.isPlaying
                                        ? Icons.graphic_eq
                                        : Icons.music_note,
                                  ),
                                  title: Text(
                                    track.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.download),
                                        tooltip: 'Download / Convert',
                                        onPressed: () =>
                                            _showDownloadDialog(index, track),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline),
                                        tooltip: 'Remove from playlist',
                                        onPressed: () =>
                                            _handleRemoveTrack(index),
                                      ),
                                    ],
                                  ),
                                  onTap: () => _controller.selectTrack(index),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EqSliderRow extends StatelessWidget {
  const _EqSliderRow({
    required this.label,
    required this.subtitle,
    required this.gainDb,
    required this.onChanged,
  });

  final String label;
  final String subtitle;
  final double gainDb;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final formattedGain =
        '${gainDb > 0 ? '+' : ''}${gainDb.toStringAsFixed(1)} dB';

    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.titleSmall),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        Expanded(
          child: Slider(
            value: gainDb,
            min: -12.0,
            max: 12.0,
            divisions: 48,
            label: formattedGain,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 68,
          child: Text(
            formattedGain,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
