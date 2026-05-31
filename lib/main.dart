import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:workmanager/workmanager.dart';

const String _eventsKey = 'workmanager_demo_events';
const String _demoTaskName = 'workmanager_demo_task';
const String _demoUniqueName = 'workmanager_demo_unique';
const int _maxStoredEvents = 12;

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final requestedAtValue = inputData?['requestedAt'] as String?;
    final requestedAt = requestedAtValue == null ? null : DateTime.tryParse(requestedAtValue);
    final finishedAt = DateTime.now();
    final elapsed = requestedAt == null ? null : finishedAt.difference(requestedAt);

    await DemoLogStorage.appendEvent(
      elapsed == null ? 'Ran at ${DemoLogStorage.formatTime(finishedAt)}.' : '${DemoLogStorage.formatTime(requestedAt!)} ran after ${elapsed.inSeconds}s.',
      source: 'WorkManager',
    );
    return true;
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    await Workmanager().initialize(callbackDispatcher);
  } else {
    // Workmanager is not supported on web; skip initialization to avoid
    // PluginUtilities.getCallbackHandle throwing UnimplementedError.
    // The UI already displays a helpful message when running on web.
  }

  runApp(const MyApp());
}

class DemoLogStorage {
  static Future<List<String>> loadEvents() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    return preferences.getStringList(_eventsKey) ?? <String>[];
  }

  static Future<void> appendEvent(String message, {String source = 'App'}) async {
    final preferences = await SharedPreferences.getInstance();
    final events = preferences.getStringList(_eventsKey) ?? <String>[];
    events.add('[${_timestamp()}][$source] $message');
    if (events.length > _maxStoredEvents) {
      events.removeRange(0, events.length - _maxStoredEvents);
    }
    await preferences.setStringList(_eventsKey, events);
  }

  static Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_eventsKey);
  }

  static String formatTime(DateTime value) {
    return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}:${value.second.toString().padLeft(2, '0')}';
  }

  static String _timestamp() {
    return formatTime(DateTime.now());
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Workmanager live demo',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E), brightness: Brightness.light),
        scaffoldBackgroundColor: const Color(0xFFF4F7F5),
      ),
      home: const DemoHomePage(),
    );
  }
}

class DemoHomePage extends StatefulWidget {
  const DemoHomePage({super.key});

  @override
  State<DemoHomePage> createState() => _DemoHomePageState();
}

class _DemoHomePageState extends State<DemoHomePage> {
  final List<String> _events = <String>[];
  final Uuid _uuid = const Uuid();
  bool _loading = true;
  bool _scheduling = false;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    final events = await DemoLogStorage.loadEvents();
    if (!mounted) {
      return;
    }
    setState(() {
      _events
        ..clear()
        ..addAll(events);
      _loading = false;
    });
  }

  Future<void> _scheduleBackgroundDemo() async {
    if (kIsWeb) {
      _showMessage('This demo runs on Android or iOS, not on web.');
      return;
    }

    setState(() {
      _scheduling = true;
    });

    try {
      final uniqueWorkName = '$_demoUniqueName-${_uuid.v4()}';

      await Workmanager().registerOneOffTask(
        uniqueWorkName,
        _demoTaskName,
        initialDelay: const Duration(seconds: 10),
        existingWorkPolicy: ExistingWorkPolicy.replace,
        inputData: <String, dynamic>{'label': 'demo', 'requestedAt': DateTime.now().toIso8601String()},
        constraints: Constraints(
          networkType: NetworkType.notRequired,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresBatteryNotLow: false,
          requiresStorageNotLow: false,
        ),
      );

      await DemoLogStorage.appendEvent('Queued task.', source: 'UI');
      await _loadEvents();
      _showMessage('Task scheduled for 10 seconds from now.');
    } catch (error) {
      _showMessage('Failed to schedule task: $error');
    } finally {
      if (mounted) {
        setState(() {
          _scheduling = false;
        });
      }
    }
  }

  Future<void> _refreshLog() async {
    if (_refreshing) {
      return;
    }

    setState(() {
      _refreshing = true;
    });

    try {
      await _loadEvents();
      _showMessage('Log refreshed.');
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _clearLog() async {
    await DemoLogStorage.clear();
    await _loadEvents();
    _showMessage('Log cleared.');
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message), duration: const Duration(milliseconds: 900)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final highlight = theme.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Workmanager live demo'),
        backgroundColor: theme.colorScheme.surface.withOpacity(0.9),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HeroCard(
                accent: highlight,
                scheduling: _scheduling,
                refreshing: _refreshing,
                onSchedule: _scheduleBackgroundDemo,
                onRefresh: _refreshLog,
                onClear: _clearLog,
              ),
              const SizedBox(height: 16),
              Text('Live event log', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              if (_loading)
                const Center(
                  child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
                )
              else
                _EventList(events: _events),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.accent,
    required this.scheduling,
    required this.refreshing,
    required this.onSchedule,
    required this.onRefresh,
    required this.onClear,
  });

  final Color accent;
  final bool scheduling;
  final bool refreshing;
  final VoidCallback onSchedule;
  final VoidCallback onRefresh;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[accent, accent.withValues(alpha: 0.78)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: <BoxShadow>[
          BoxShadow(color: accent.withValues(alpha: 0.25), blurRadius: 28, offset: const Offset(0, 16)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Flutter background execution',
                style: theme.textTheme.labelLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Workmanager demo',
              style: theme.textTheme.headlineMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Schedule a one-off job, send the app to the background, then refresh the log to show the result.',
              style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white.withValues(alpha: 0.92), height: 1.35),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: scheduling ? null : onSchedule,
                  icon: scheduling
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.schedule),
                  label: Text(scheduling ? 'Scheduling...' : 'Schedule demo task'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: accent),
                ),
                OutlinedButton.icon(
                  onPressed: refreshing ? null : onRefresh,
                  icon: refreshing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(refreshing ? 'Refreshing...' : 'Refresh log'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white70),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Clear log'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white70),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EventList extends StatelessWidget {
  const _EventList({required this.events});

  final List<String> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return Card(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: const Padding(
          padding: EdgeInsets.all(22),
          child: Text('No events yet. Schedule the demo task, then refresh the log.'),
        ),
      );
    }

    return Column(
      children: events.reversed
          .map(
            (event) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _EventTile(text: event),
            ),
          )
          .toList(),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.event_note, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}
