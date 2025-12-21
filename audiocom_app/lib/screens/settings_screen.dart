import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/audio_provider.dart';

/// Settings Screen - audio and app settings
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade900,
      appBar: AppBar(
        backgroundColor: Colors.grey.shade800,
        title: const Text('Audio Settings'),
      ),
      body: Consumer<AudioProvider>(
        builder: (context, audio, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Bitrate Section
              Card(
                color: Colors.grey.shade800,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.speed, color: Colors.indigo),
                          const SizedBox(width: 8),
                          const Text(
                            'Audio Bitrate',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.indigo,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${audio.audioBitrateKbps} kbps',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: Colors.indigo,
                          inactiveTrackColor: Colors.grey.shade700,
                          thumbColor: Colors.indigo,
                          overlayColor: Colors.indigo.withOpacity(0.2),
                          valueIndicatorColor: Colors.indigo,
                          valueIndicatorTextStyle: const TextStyle(color: Colors.white),
                        ),
                        child: Slider(
                          value: audio.audioBitrateKbps.toDouble(),
                          min: 8,
                          max: 128,
                          divisions: 15, // 8, 16, 24, 32, 40, 48, 56, 64, 72, 80, 88, 96, 104, 112, 120, 128
                          label: '${audio.audioBitrateKbps} kbps',
                          onChanged: (value) {
                            audio.setAudioBitrate(value.round());
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('8 kbps', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                          Text('128 kbps', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Quick presets
                      const Text(
                        'Presets',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _BitratePresetChip(
                            label: 'Low (16)',
                            bitrate: 16,
                            currentBitrate: audio.audioBitrateKbps,
                            onTap: () => audio.setAudioBitrate(16),
                          ),
                          _BitratePresetChip(
                            label: 'Normal (32)',
                            bitrate: 32,
                            currentBitrate: audio.audioBitrateKbps,
                            onTap: () => audio.setAudioBitrate(32),
                          ),
                          _BitratePresetChip(
                            label: 'High (64)',
                            bitrate: 64,
                            currentBitrate: audio.audioBitrateKbps,
                            onTap: () => audio.setAudioBitrate(64),
                          ),
                          _BitratePresetChip(
                            label: 'Max (128)',
                            bitrate: 128,
                            currentBitrate: audio.audioBitrateKbps,
                            onTap: () => audio.setAudioBitrate(128),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Info Card
              Card(
                color: Colors.grey.shade800,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.blue.shade300),
                          const SizedBox(width: 8),
                          const Text(
                            'About Bitrate',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '• Lower bitrate = less bandwidth, lower quality\n'
                        '• Higher bitrate = more bandwidth, better quality\n'
                        '• 16-24 kbps: Good for poor connections\n'
                        '• 32 kbps: Recommended for voice chat\n'
                        '• 64+ kbps: High quality voice/music\n\n'
                        'Note: Changes apply to the next voice session.',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // WebRTC Info Card
              Card(
                color: Colors.grey.shade800,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.security, color: Colors.green.shade300),
                          const SizedBox(width: 8),
                          const Text(
                            'WebRTC Features',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _FeatureRow(icon: Icons.check_circle, text: 'DTLS-SRTP Encryption', enabled: true),
                      _FeatureRow(icon: Icons.check_circle, text: 'Jitter Buffer (latency handling)', enabled: true),
                      _FeatureRow(icon: Icons.check_circle, text: 'Packet Loss Concealment (PLC)', enabled: true),
                      _FeatureRow(icon: Icons.check_circle, text: 'Forward Error Correction (FEC)', enabled: true),
                      _FeatureRow(icon: Icons.check_circle, text: 'Opus Codec (adaptive)', enabled: true),
                      _FeatureRow(icon: Icons.check_circle, text: 'DTX (bandwidth saving)', enabled: true),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BitratePresetChip extends StatelessWidget {
  final String label;
  final int bitrate;
  final int currentBitrate;
  final VoidCallback onTap;

  const _BitratePresetChip({
    required this.label,
    required this.bitrate,
    required this.currentBitrate,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = currentBitrate == bitrate;
    return ActionChip(
      label: Text(label),
      backgroundColor: isSelected ? Colors.indigo : Colors.grey.shade700,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.grey.shade300,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      onPressed: onTap,
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool enabled;

  const _FeatureRow({
    required this.icon,
    required this.text,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: enabled ? Colors.green.shade300 : Colors.grey,
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: enabled ? Colors.grey.shade300 : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
}
