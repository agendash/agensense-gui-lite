import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/io.dart';

import 'src/agensense_api.dart';
import 'src/audio_utils.dart';

void main() {
  runApp(const AgenSenseGuiLiteApp());
}

const defaultSharedSystemPrompt =
    '''You are AgenSense, a shared voice orchestration assistant for AgenDash clients.

Respond for speech playback, not a terminal or chat transcript.
- Keep the reply to one short sentence unless the user explicitly asks for detail.
- Target 28 Chinese characters or 16 English words.
- Say the outcome, next action, or blocking issue directly.
- Do not output markdown, bullet lists, JSON, XML, ANSI escapes, or tool-call notation.
- Do not narrate hidden reasoning or internal implementation details.
- If no remote code agent is focused, stay in local assistant mode and say that a focused agent is required for remote execution.
- If the request clearly sounds like an approval, scene switch, or playback command, keep the wording brief and confirmation-oriented.''';

class SharedTestContext {
  final systemPrompt = TextEditingController(text: defaultSharedSystemPrompt);
  final scene = TextEditingController(text: 'gui-lite-tool-test');
  final target = TextEditingController(text: 'workspace');
  final action = TextEditingController(text: 'inspect');
  final args = TextEditingController(
    text: '{\n  "path": ".",\n  "mode": "read_only"\n}',
  );
  final mcpServers = TextEditingController(
    text:
        '{\n  "filesystem": {\n    "transport": "stdio",\n    "tools": ["list_files", "read_file"]\n  }\n}',
  );

  void dispose() {
    systemPrompt.dispose();
    scene.dispose();
    target.dispose();
    action.dispose();
    args.dispose();
    mcpServers.dispose();
  }
}

class AgenSenseGuiLiteApp extends StatelessWidget {
  const AgenSenseGuiLiteApp({super.key});

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xff17201d);
    const fieldBorder = Color(0xffd7ddd5);
    const primary = Color(0xff0d665f);
    const accent = Color(0xff9f5f26);
    const quietBlue = Color(0xff315f7a);
    const appSurface = Color(0xfff3f1ea);
    const panelSurface = Color(0xfffffdf8);
    const fieldSurface = Color(0xfffaf8f1);

    const scheme = ColorScheme.light(
      primary: primary,
      onPrimary: Colors.white,
      primaryContainer: Color(0xffd7eee9),
      onPrimaryContainer: Color(0xff053b36),
      secondary: accent,
      onSecondary: Colors.white,
      secondaryContainer: Color(0xffffe2c4),
      onSecondaryContainer: Color(0xff4b2607),
      tertiary: quietBlue,
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xffd9ecf5),
      onTertiaryContainer: Color(0xff0a3145),
      surface: panelSurface,
      onSurface: ink,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: Color(0xfffbfaf5),
      surfaceContainer: Color(0xfff0eee7),
      surfaceContainerHigh: Color(0xffe7e4dc),
      outline: fieldBorder,
      outlineVariant: Color(0xffe5e8e1),
      error: Color(0xffad2f2f),
    );
    return MaterialApp(
      title: 'AgenSense GUI Lite',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: appSurface,
        visualDensity: VisualDensity.compact,
        appBarTheme: const AppBarTheme(
          backgroundColor: panelSurface,
          foregroundColor: ink,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: ink,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        cardTheme: const CardThemeData(
          elevation: 0,
          color: panelSurface,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            side: BorderSide(color: fieldBorder),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          filled: true,
          fillColor: fieldSurface,
          isDense: true,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: primary,
            side: const BorderSide(color: Color(0xffb8c6be)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        chipTheme: const ChipThemeData(
          backgroundColor: Color(0xffe9e5d8),
          selectedColor: Color(0xffd7eee9),
          labelStyle: TextStyle(color: ink),
          side: BorderSide(color: Color(0xffd7d2c4)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: primary,
          unselectedLabelColor: Color(0xff68736d),
          indicatorColor: primary,
          dividerColor: Color(0xffdedbd2),
        ),
        listTileTheme: const ListTileThemeData(
          iconColor: quietBlue,
          textColor: ink,
        ),
      ),
      home: const AgenSenseHome(),
    );
  }
}

class AgenSenseHome extends StatefulWidget {
  const AgenSenseHome({super.key});

  @override
  State<AgenSenseHome> createState() => _AgenSenseHomeState();
}

class _AgenSenseHomeState extends State<AgenSenseHome>
    with SingleTickerProviderStateMixin {
  static const _tabCount = 7;

  late final TabController _tabController;
  final _voiceTabKey = GlobalKey<_VoiceWSTabState>();
  final _sharedContext = SharedTestContext();
  final _baseUrl = TextEditingController(text: 'http://127.0.0.1:8080');
  final _apiKey = TextEditingController(text: 'demo-user-key');
  final _profile = TextEditingController(text: 'default');
  final _clientId = TextEditingController(text: 'agensense-gui-lite');
  final _deviceLabel = TextEditingController(text: Platform.operatingSystem);

  bool _loadingPrefs = true;
  bool _configDialogOpen = false;
  String _status = 'Not checked';
  int _lastTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabCount, vsync: this)
      ..addListener(_handleTabChange);
    _loadPrefs();
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    _baseUrl.dispose();
    _apiKey.dispose();
    _profile.dispose();
    _clientId.dispose();
    _deviceLabel.dispose();
    _sharedContext.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    final index = _tabController.index;
    if (index == _lastTabIndex) {
      return;
    }
    if (_lastTabIndex == 0 && index != 0) {
      unawaited(_voiceTabKey.currentState?.stopForTabSwitch());
    }
    _lastTabIndex = index;
  }

  AppConfig _config() {
    return AppConfig(
      baseUrl: _baseUrl.text,
      apiKey: _apiKey.text,
      providerProfileId: _profile.text,
      clientId: _clientId.text,
      deviceLabel: _deviceLabel.text,
      sampleRateHz: 16000,
      channels: 1,
    );
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl.text = prefs.getString('base_url') ?? _baseUrl.text;
    _apiKey.text = prefs.getString('api_key') ?? _apiKey.text;
    _profile.text = prefs.getString('provider_profile_id') ?? _profile.text;
    _clientId.text = prefs.getString('client_id') ?? _clientId.text;
    _deviceLabel.text = prefs.getString('device_label') ?? _deviceLabel.text;
    if (!mounted) {
      return;
    }
    setState(() => _loadingPrefs = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _showConnectionDialog(requiredSetup: true);
      }
    });
  }

  String? _validateConnection() {
    final uri = Uri.tryParse(_baseUrl.text.trim());
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return 'Server URL must be a valid http:// or https:// URL.';
    }
    if (_apiKey.text.trim().isEmpty) {
      return 'API key is required.';
    }
    if (_profile.text.trim().isEmpty) {
      return 'Provider profile is required.';
    }
    if (_clientId.text.trim().isEmpty) {
      return 'Client ID is required.';
    }
    return null;
  }

  Future<bool> _savePrefs() async {
    final error = _validateConnection();
    if (error != null) {
      setState(() => _status = error);
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('base_url', _baseUrl.text.trim());
    await prefs.setString('api_key', _apiKey.text.trim());
    await prefs.setString('provider_profile_id', _profile.text.trim());
    await prefs.setString('client_id', _clientId.text.trim());
    await prefs.setString('device_label', _deviceLabel.text.trim());
    if (!mounted) {
      return false;
    }
    setState(() => _status = 'Saved locally');
    return true;
  }

  Future<void> _showConnectionDialog({required bool requiredSetup}) async {
    if (_configDialogOpen) {
      return;
    }
    _configDialogOpen = true;
    var dialogStatus = requiredSetup
        ? 'Confirm the AgenSense server before using this client.'
        : _status;
    var healthBusy = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: !requiredSetup,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, dialogSetState) {
            Future<void> checkHealth() async {
              final error = _validateConnection();
              if (error != null) {
                setState(() => _status = error);
                dialogSetState(() => dialogStatus = error);
                return;
              }
              dialogSetState(() {
                healthBusy = true;
                dialogStatus = 'Checking AgenSense...';
              });
              try {
                final result = await AgenSenseApi(_config()).health();
                final nextStatus = 'Healthy: ${prettyJson(result)}';
                if (!mounted) {
                  return;
                }
                setState(() => _status = nextStatus);
                dialogSetState(() => dialogStatus = nextStatus);
              } catch (error) {
                final nextStatus = 'Health check failed: $error';
                if (!mounted) {
                  return;
                }
                setState(() => _status = nextStatus);
                dialogSetState(() => dialogStatus = nextStatus);
              } finally {
                if (mounted) {
                  dialogSetState(() => healthBusy = false);
                }
              }
            }

            Future<void> saveAndClose() async {
              final saved = await _savePrefs();
              dialogSetState(() => dialogStatus = _status);
              if (saved && dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            }

            return PopScope(
              canPop: !requiredSetup,
              child: AlertDialog(
                title: const Row(
                  children: [
                    Icon(Icons.settings_outlined),
                    SizedBox(width: 10),
                    Text('AgenSense connection'),
                  ],
                ),
                content: SizedBox(
                  width: 720,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Set the server connection once, then use the settings button in the top-right corner to change it later.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            SizedBox(
                              width: 336,
                              child: field(
                                _baseUrl,
                                'Server URL',
                                Icons.link_outlined,
                              ),
                            ),
                            SizedBox(
                              width: 336,
                              child: field(
                                _apiKey,
                                'API key',
                                Icons.key_outlined,
                                obscure: true,
                              ),
                            ),
                            SizedBox(
                              width: 216,
                              child: field(
                                _profile,
                                'Provider profile',
                                Icons.tune_outlined,
                              ),
                            ),
                            SizedBox(
                              width: 236,
                              child: field(
                                _clientId,
                                'Client ID',
                                Icons.badge_outlined,
                              ),
                            ),
                            SizedBox(
                              width: 216,
                              child: field(
                                _deviceLabel,
                                'Device label',
                                Icons.devices_outlined,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                          child: Text(
                            dialogStatus,
                            maxLines: 5,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  if (!requiredSetup)
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Cancel'),
                    ),
                  OutlinedButton.icon(
                    onPressed: healthBusy ? null : checkHealth,
                    icon: healthBusy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.monitor_heart_outlined),
                    label: const Text('Health'),
                  ),
                  FilledButton.icon(
                    onPressed: saveAndClose,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    _configDialogOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingPrefs) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('AgenSense GUI Lite'),
        actions: [
          IconButton(
            tooltip: 'Connection settings',
            onPressed: () => _showConnectionDialog(requiredSetup: false),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabs: [
                Tab(
                  icon: Icon(Icons.settings_voice_outlined),
                  text: 'Voice WS',
                ),
                Tab(icon: Icon(Icons.chat_bubble_outline), text: 'LLM + Tool'),
                Tab(icon: Icon(Icons.record_voice_over_outlined), text: 'ASR'),
                Tab(icon: Icon(Icons.graphic_eq_outlined), text: 'TTS'),
                Tab(icon: Icon(Icons.hub_outlined), text: 'Providers'),
                Tab(icon: Icon(Icons.developer_board_outlined), text: 'Device'),
                Tab(icon: Icon(Icons.bug_report_outlined), text: 'Debug'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                VoiceWSTab(
                  key: _voiceTabKey,
                  config: _config,
                  shared: _sharedContext,
                ),
                ChatToolTab(config: _config, shared: _sharedContext),
                ASRTab(config: _config),
                TTSTab(config: _config),
                ProvidersTab(config: _config),
                DeviceTab(config: _config),
                DebugTab(config: _config),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ProvidersTab extends StatefulWidget {
  const ProvidersTab({super.key, required this.config});

  final AppConfig Function() config;

  @override
  State<ProvidersTab> createState() => _ProvidersTabState();
}

class _ProvidersTabState extends State<ProvidersTab> {
  final _id = TextEditingController(text: 'default');
  final _name = TextEditingController(text: 'LocalAI Default');
  final _baseUrl = TextEditingController(text: 'http://127.0.0.1:8081/v1');
  final _apiKey = TextEditingController();
  final _asrModel = TextEditingController(text: 'whisper-1');
  final _llmModel = TextEditingController(
    text: 'hauhaucs-qwen3.6-35b-a3b-aggressive-q4-k-m',
  );
  final _ttsModel = TextEditingController(text: 'faster-qwen3-tts');

  bool _makeDefault = true;
  bool _busy = false;
  List<ProviderProfile> _profiles = const <ProviderProfile>[];
  String _output = 'List providers or register a LocalAI/mock profile.';

  @override
  void dispose() {
    _id.dispose();
    _name.dispose();
    _baseUrl.dispose();
    _apiKey.dispose();
    _asrModel.dispose();
    _llmModel.dispose();
    _ttsModel.dispose();
    super.dispose();
  }

  Future<void> _listProviders() async {
    await _run(() async {
      final profiles = await AgenSenseApi(widget.config()).listProviders();
      setState(() {
        _profiles = profiles;
        _output = prettyJson({
          'count': profiles.length,
          'items': profiles.map((item) => item.id).toList(),
        });
      });
    });
  }

  Future<void> _registerLocalAI() async {
    await _run(() async {
      final body = _profileBody(
        id: _id.text.trim().isEmpty ? 'default' : _id.text.trim(),
        name: _name.text.trim().isEmpty ? 'LocalAI Default' : _name.text.trim(),
        baseUrl: _baseUrl.text.trim(),
        apiKey: _apiKey.text.trim(),
        asrModel: _asrModel.text.trim(),
        llmModel: _llmModel.text.trim(),
        ttsModel: _ttsModel.text.trim(),
      );
      final result = await AgenSenseApi(widget.config()).upsertProvider(body);
      setState(() => _output = prettyJson(result));
      await _listProviders();
    });
  }

  Future<void> _registerMock() async {
    await _run(() async {
      final body = _profileBody(
        id: 'mock-default',
        name: 'Mock Provider',
        baseUrl: 'mock://provider',
        apiKey: '',
        asrModel: 'mock-asr',
        llmModel: 'mock-llm',
        ttsModel: 'mock-tts',
      );
      final result = await AgenSenseApi(widget.config()).upsertProvider(body);
      setState(() => _output = prettyJson(result));
      await _listProviders();
    });
  }

  Map<String, dynamic> _profileBody({
    required String id,
    required String name,
    required String baseUrl,
    required String apiKey,
    required String asrModel,
    required String llmModel,
    required String ttsModel,
  }) {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'asr_base_url': baseUrl,
      if (apiKey.isNotEmpty) 'asr_api_key': apiKey,
      'asr_model': asrModel,
      'llm_base_url': baseUrl,
      if (apiKey.isNotEmpty) 'llm_api_key': apiKey,
      'llm_model': llmModel,
      'tts_base_url': baseUrl,
      if (apiKey.isNotEmpty) 'tts_api_key': apiKey,
      'tts_model': ttsModel,
      'default': _makeDefault,
    };
  }

  Future<void> _run(Future<void> Function() task) async {
    setState(() => _busy = true);
    try {
      await task();
    } catch (error) {
      if (mounted) {
        setState(() => _output = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return TwoPaneTab(
      left: [
        SectionTitle(
          icon: Icons.hub_outlined,
          title: 'Provider profile',
          subtitle: 'Register reusable ASR, LLM, and TTS upstream settings.',
        ),
        field(_id, 'Profile ID', Icons.fingerprint_outlined),
        field(_name, 'Name', Icons.label_outline),
        field(_baseUrl, 'OpenAI-compatible base URL', Icons.dns_outlined),
        field(
          _apiKey,
          'Provider API key',
          Icons.vpn_key_outlined,
          obscure: true,
        ),
        field(_asrModel, 'ASR model', Icons.hearing_outlined),
        field(_llmModel, 'LLM model', Icons.psychology_alt_outlined),
        field(_ttsModel, 'TTS model', Icons.spatial_audio_off_outlined),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _makeDefault,
          title: const Text('Set as default for this AgenSense API key'),
          onChanged: (value) => setState(() => _makeDefault = value ?? true),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _registerLocalAI,
              icon: const Icon(Icons.cloud_sync_outlined),
              label: const Text('Register LocalAI'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _registerMock,
              icon: const Icon(Icons.science_outlined),
              label: const Text('Register mock'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _listProviders,
              icon: const Icon(Icons.refresh_outlined),
              label: const Text('List'),
            ),
          ],
        ),
      ],
      right: [
        SectionTitle(
          icon: Icons.list_alt_outlined,
          title: 'Stored profiles',
          subtitle: 'Profiles are scoped by the AgenSense API key.',
        ),
        if (_busy) const LinearProgressIndicator(),
        ..._profiles.map((profile) => ProviderProfileTile(profile: profile)),
        LogPanel(text: _output),
      ],
    );
  }
}

class ChatToolTab extends StatefulWidget {
  const ChatToolTab({super.key, required this.config, required this.shared});

  final AppConfig Function() config;
  final SharedTestContext shared;

  @override
  State<ChatToolTab> createState() => _ChatToolTabState();
}

class _ChatToolTabState extends State<ChatToolTab> {
  final _user = TextEditingController(
    text: 'Say hello and report your model path.',
  );

  bool _includeToolMetadata = true;
  bool _streamResponse = true;
  bool _busy = false;
  String _reply = 'Send a normal chat request or run the tool-use probe.';
  String _raw = '';

  @override
  void dispose() {
    _user.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    var receivedDelta = false;
    setState(() {
      _busy = true;
      _reply = _streamResponse
          ? 'Waiting for first token...'
          : 'Waiting for response...';
      _raw = '';
    });
    try {
      final voiceAssistant = _includeToolMetadata
          ? <String, dynamic>{
              'contract': 'universal_voice_layer_v1',
              'ui_context': {
                'current_scene': widget.shared.scene.text.trim(),
                'client_surface': 'agensense-gui-lite',
              },
              'assistant_intent': {
                'scope': 'mcp',
                'target_id': widget.shared.target.text.trim(),
                'action': widget.shared.action.text.trim(),
                'args': parseJsonObject(widget.shared.args.text),
                'ui_surface': 'flutter-validation-client',
                'label': 'Tool-use validation probe',
              },
              'metadata': {
                'shared_system_prompt': widget.shared.systemPrompt.text.trim(),
                'mcp_servers': parseJsonObject(widget.shared.mcpServers.text),
                'note':
                    'AgenSense stores this metadata for traceability; clients still provide the tool contract in messages.',
              },
            }
          : null;
      final messages = <Map<String, String>>[
        {'role': 'system', 'content': widget.shared.systemPrompt.text.trim()},
        if (_includeToolMetadata)
          {
            'role': 'system',
            'content':
                'Tool-use probe: if a tool is needed, describe the MCP server, tool name, arguments, and safety checks. Do not execute external tools.',
          },
        {'role': 'user', 'content': _user.text.trim()},
      ];
      final api = AgenSenseApi(widget.config());
      final response = _streamResponse
          ? await api.chatStream(
              messages: messages,
              voiceAssistant: voiceAssistant,
              onDelta: (delta) {
                if (!mounted) {
                  return;
                }
                setState(() {
                  if (!receivedDelta) {
                    _reply = '';
                    receivedDelta = true;
                  }
                  _reply += delta;
                });
              },
            )
          : await api.chat(messages: messages, voiceAssistant: voiceAssistant);
      if (!mounted) {
        return;
      }
      setState(() {
        _reply = response.text;
        _raw = prettyJson(response.raw);
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _reply = error.toString();
          _raw = '';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _fillProbe() {
    widget.shared.systemPrompt.text =
        'You are validating an MCP/tool-use capable client. Reply with a concise tool plan and include the selected tool arguments.';
    _user.text =
        'Inspect the current workspace and tell me what files you would read first before making a change.';
    widget.shared.scene.text = 'mcp-tooluse-validation';
    widget.shared.target.text = 'filesystem';
    widget.shared.action.text = 'list_files';
    widget.shared.args.text = '{\n  "path": ".",\n  "max_depth": 2\n}';
    setState(() => _includeToolMetadata = true);
  }

  @override
  Widget build(BuildContext context) {
    final promptPanel = Panel(
      children: [
        const SectionTitle(
          icon: Icons.chat_bubble_outline,
          title: 'Prompts',
          subtitle:
              'Shared system prompt used by LLM + Tool and Voice WS tests.',
        ),
        field(
          widget.shared.systemPrompt,
          'Shared system prompt',
          Icons.notes_outlined,
          maxLines: 8,
        ),
        field(_user, 'User message', Icons.person_outline, maxLines: 6),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilterChip(
              selected: _streamResponse,
              onSelected: _busy
                  ? null
                  : (value) => setState(() => _streamResponse = value),
              avatar: const Icon(Icons.stream_outlined),
              label: const Text('Stream'),
            ),
            FilledButton.icon(
              onPressed: _busy ? null : _send,
              icon: const Icon(Icons.send_outlined),
              label: const Text('Send'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _fillProbe,
              icon: const Icon(Icons.auto_fix_high_outlined),
              label: const Text('Fill probe'),
            ),
          ],
        ),
      ],
    );

    final toolPanel = Panel(
      children: [
        const SectionTitle(
          icon: Icons.integration_instructions_outlined,
          title: 'Tool-use',
          subtitle: 'Universal Voice Layer and MCP metadata for trace testing.',
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _includeToolMetadata,
          title: const Text('Include Universal Voice Layer / MCP metadata'),
          onChanged: (value) =>
              setState(() => _includeToolMetadata = value ?? true),
        ),
        if (_includeToolMetadata) ...[
          field(
            widget.shared.scene,
            'UI scene',
            Icons.dashboard_customize_outlined,
          ),
          field(
            widget.shared.target,
            'Target / MCP server',
            Icons.account_tree_outlined,
          ),
          field(
            widget.shared.action,
            'Action / tool name',
            Icons.build_outlined,
          ),
          field(
            widget.shared.args,
            'Tool args JSON',
            Icons.data_object_outlined,
            maxLines: 6,
          ),
          field(
            widget.shared.mcpServers,
            'MCP servers JSON',
            Icons.integration_instructions_outlined,
            maxLines: 6,
          ),
        ] else
          Text(
            'Tool metadata is disabled. The request will contain only chat messages.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
      ],
    );

    final responsePanel = Panel(
      children: [
        const SectionTitle(
          icon: Icons.output_outlined,
          title: 'Response',
          subtitle:
              'Streamed deltas are shown live; the final event keeps raw JSON.',
        ),
        if (_busy) const LinearProgressIndicator(),
        LogPanel(text: _reply),
        if (_raw.isNotEmpty) LogPanel(text: _raw, title: 'Raw JSON'),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 980;
        if (narrow) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              promptPanel,
              const SizedBox(height: 16),
              toolPanel,
              const SizedBox(height: 16),
              responsePanel,
            ],
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: promptPanel),
                const SizedBox(width: 16),
                Expanded(child: toolPanel),
              ],
            ),
            const SizedBox(height: 16),
            responsePanel,
          ],
        );
      },
    );
  }
}

class ASRTab extends StatefulWidget {
  const ASRTab({super.key, required this.config});

  final AppConfig Function() config;

  @override
  State<ASRTab> createState() => _ASRTabState();
}

class _ASRTabState extends State<ASRTab> {
  final _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _recordSub;
  StreamSubscription? _streamSocketSub;
  IOWebSocketChannel? _streamChannel;
  BytesBuilder _audio = BytesBuilder(copy: false);
  bool _recording = false;
  bool _busy = false;
  bool _streamASR = false;
  int _bytes = 0;
  int _streamSeq = 0;
  String? _streamId;
  String _output =
      'Record PCM audio or load a raw .pcm file, then transcribe it.';

  @override
  void dispose() {
    unawaited(_recordSub?.cancel());
    unawaited(_streamSocketSub?.cancel());
    unawaited(_streamChannel?.sink.close());
    unawaited(_recorder.dispose());
    super.dispose();
  }

  Future<void> _startRecording() async {
    try {
      if (!await _recorder.hasPermission()) {
        setState(() => _output = 'Microphone permission was denied.');
        return;
      }
      if (!await _recorder.isEncoderSupported(AudioEncoder.pcm16bits)) {
        setState(() => _output = 'pcm16bits recording is not supported here.');
        return;
      }
      final config = widget.config();
      _audio = BytesBuilder(copy: false);
      _bytes = 0;
      _streamSeq = 0;
      if (_streamASR) {
        await _connectASRStream(config);
      }
      final stream = await _recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: config.sampleRateHz,
          numChannels: config.channels,
          streamBufferSize: 3200,
        ),
      );
      _recordSub = stream.listen((chunk) {
        if (_streamASR) {
          _streamSeq++;
          _streamChannel?.sink.add(chunk);
        } else {
          _audio.add(chunk);
        }
        if (mounted) {
          setState(() => _bytes += chunk.length);
        }
      });
      setState(() {
        _recording = true;
        _output = _streamASR
            ? 'Streaming PCM to /v1/voice/ws for ASR partials...'
            : 'Recording raw PCM...';
      });
    } catch (error) {
      setState(() => _output = error.toString());
    }
  }

  Future<void> _stopAndTranscribe() async {
    setState(() => _busy = true);
    try {
      await _recorder.stop();
      await _recordSub?.cancel();
      _recordSub = null;
      if (_streamASR) {
        final streamId = _streamId;
        if (streamId != null) {
          _sendASRStreamEvent('audio.stop', {
            'stream_id': streamId,
            'last_seq': _streamSeq,
          });
        }
        setState(() {
          _recording = false;
          _output = '${_output.trim()}\n\nWaiting for streaming asr.final...';
        });
        return;
      }
      final audio = _audio.toBytes();
      setState(() => _recording = false);
      await _transcribe(audio);
    } catch (error) {
      if (mounted) {
        setState(() => _output = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _connectASRStream(AppConfig config) async {
    await _streamSocketSub?.cancel();
    await _streamChannel?.sink.close();
    final uri = wsUri(config.normalizedBaseUrl, '/v1/voice/ws');
    final channel = IOWebSocketChannel.connect(
      uri,
      headers: {'authorization': 'Bearer ${config.apiKey.trim()}'},
      pingInterval: const Duration(seconds: 20),
      connectTimeout: const Duration(seconds: 15),
    );
    await channel.ready;
    _streamChannel = channel;
    _streamSocketSub = channel.stream.listen(
      _handleASRStreamEvent,
      onError: (Object error) {
        if (mounted) {
          setState(() => _output = '${_output.trim()}\n\nsocket.error $error');
        }
      },
      onDone: () {
        if (mounted && _busy) {
          setState(() => _busy = false);
        }
      },
    );
    _streamId = 'asr-${DateTime.now().millisecondsSinceEpoch}';
    _sendASRStreamEvent('session.update', {
      'client_id': config.clientId.trim(),
      'device_label': config.deviceLabel.trim(),
      'session_id': newSessionId('asr-stream'),
      'provider_profile_id': config.providerProfileId.trim(),
      'auto_response': false,
      'format': audioFormat(config),
    });
    _sendASRStreamEvent('audio.start', {
      'stream_id': _streamId,
      'codec': 'pcm_s16le',
      'sample_rate_hz': config.sampleRateHz,
      'channels': config.channels,
    });
  }

  void _handleASRStreamEvent(Object? event) {
    if (event is! String) {
      return;
    }
    final decoded = jsonDecode(event) as Map<String, dynamic>;
    final type = stringValue(decoded['type']);
    final payload = asMap(decoded['payload']);
    if (type == 'asr.partial') {
      final text = stringValue(payload['text']);
      if (mounted && text.isNotEmpty) {
        setState(() => _output = 'partial: $text');
      }
      return;
    }
    if (type == 'asr.final') {
      final text = stringValue(payload['text']);
      if (mounted) {
        setState(() {
          _busy = false;
          _output = prettyJson({
            'mode': 'stream',
            'final': text,
            'bytes': _bytes,
            'frames': _streamSeq,
          });
        });
      }
      unawaited(_streamSocketSub?.cancel());
      _streamSocketSub = null;
      unawaited(_streamChannel?.sink.close());
      _streamChannel = null;
      return;
    }
    if (type == 'error' && mounted) {
      setState(() {
        _busy = false;
        _output = '${_output.trim()}\n\n${compact(decoded)}';
      });
    }
  }

  void _sendASRStreamEvent(String type, Map<String, dynamic> payload) {
    final message = {
      'type': type,
      'request_id': 'asr-${DateTime.now().millisecondsSinceEpoch}',
      'payload': payload,
    };
    _streamChannel?.sink.add(jsonEncode(message));
  }

  Future<void> _pickPCM() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pcm', 'raw'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }
    Uint8List? data = result.files.single.bytes;
    final path = result.files.single.path;
    if (data == null && path != null) {
      data = await File(path).readAsBytes();
    }
    if (data == null) {
      setState(() => _output = 'Could not read selected PCM file.');
      return;
    }
    await _transcribe(data);
  }

  Future<void> _transcribe(Uint8List audio) async {
    if (audio.isEmpty) {
      setState(() => _output = 'No audio captured.');
      return;
    }
    setState(() {
      _busy = true;
      _bytes = audio.length;
      _output = 'Sending ${audio.length} bytes to /v1/asr/transcribe...';
    });
    try {
      final response = await AgenSenseApi(widget.config()).transcribe(audio);
      if (!mounted) {
        return;
      }
      setState(() => _output = prettyJson(response));
    } catch (error) {
      if (mounted) {
        setState(() => _output = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SinglePaneTab(
      children: [
        SectionTitle(
          icon: Icons.record_voice_over_outlined,
          title: 'ASR direct test',
          subtitle:
              'Records pcm_s16le, 16 kHz, mono audio and calls /v1/asr/transcribe.',
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilterChip(
              selected: _streamASR,
              onSelected: _recording || _busy
                  ? null
                  : (value) => setState(() => _streamASR = value),
              avatar: const Icon(Icons.stream_outlined),
              label: const Text('Stream'),
            ),
            FilledButton.icon(
              onPressed: _busy || _recording ? null : _startRecording,
              icon: const Icon(Icons.mic_outlined),
              label: const Text('Record'),
            ),
            FilledButton.tonalIcon(
              onPressed: _recording ? _stopAndTranscribe : null,
              icon: const Icon(Icons.stop_circle_outlined),
              label: Text(_streamASR ? 'Stop stream' : 'Stop + transcribe'),
            ),
            OutlinedButton.icon(
              onPressed: _busy || _recording ? null : _pickPCM,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Load PCM'),
            ),
            Chip(
              avatar: const Icon(Icons.memory_outlined),
              label: Text('$_bytes bytes'),
            ),
          ],
        ),
        if (_busy) const LinearProgressIndicator(),
        LogPanel(text: _output),
      ],
    );
  }
}

class TTSTab extends StatefulWidget {
  const TTSTab({super.key, required this.config});

  final AppConfig Function() config;

  @override
  State<TTSTab> createState() => _TTSTabState();
}

class _TTSTabState extends State<TTSTab> {
  final _text = TextEditingController(text: '你好，我是 AgenSense 女声语音验证客户端。');
  final _player = AudioPlayer();
  bool _busy = false;
  String _output = 'Synthesize text and play the returned audio.';
  String? _lastFile;

  @override
  void dispose() {
    _text.dispose();
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _synthesize() async {
    setState(() {
      _busy = true;
      _output = 'Sending /v1/tts/synthesize...';
    });
    try {
      final startedAt = DateTime.now();
      final response = await AgenSenseApi(
        widget.config(),
      ).synthesize(_text.text);
      final responseAt = DateTime.now();
      final wav = ensureWavAudio(
        audio: response.audio,
        codec: response.codec,
        sampleRateHz: response.sampleRateHz,
        channels: response.channels,
      );
      final dir = await _ttsOutputDir();
      final file = File(
        '${dir.path}/agensense_tts_${DateTime.now().millisecondsSinceEpoch}.wav',
      );
      await file.writeAsBytes(wav, flush: true);
      final fileExists = await file.exists();
      final fileBytes = fileExists ? await file.length() : 0;
      if (!fileExists || fileBytes <= 0) {
        throw FileSystemException(
          'TTS WAV write verification failed',
          file.path,
        );
      }
      if (!mounted) {
        return;
      }
      final summary = {
        'status': 'received_audio',
        'elapsed_ms': DateTime.now().difference(startedAt).inMilliseconds,
        'provider_elapsed_ms': responseAt.difference(startedAt).inMilliseconds,
        'provider_profile_id': response.providerProfileId,
        'codec': response.codec,
        'sample_rate_hz': response.sampleRateHz,
        'channels': response.channels,
        'input_audio_bytes': response.audio.length,
        'playback_wav_bytes': wav.length,
        'file_exists': fileExists,
        'file_bytes': fileBytes,
        'output_dir': dir.path,
        'chunk_count': response.chunkCount,
        'file': file.path,
      };
      setState(() {
        _lastFile = file.path;
        _output = '${prettyJson(summary)}\n\nPlaying audio...';
      });
      await _playFile(file.path);
      if (mounted) {
        setState(() => _output = prettyJson({...summary, 'status': 'played'}));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _output = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _playLast() async {
    final path = _lastFile;
    if (path == null) {
      return;
    }
    final file = File(path);
    if (!await file.exists()) {
      if (mounted) {
        setState(
          () => _output =
              '${_output.trim()}\n\nReplay failed: WAV file does not exist: $path',
        );
      }
      return;
    }
    await _playFile(path);
  }

  Future<void> _playFile(String path) async {
    final file = File(path);
    final exists = await file.exists();
    final length = exists ? await file.length() : 0;
    if (!exists || length <= 0) {
      throw FileSystemException(
        'TTS WAV file is missing before playback',
        path,
      );
    }
    await _player.stop();
    await _player.play(DeviceFileSource(path, mimeType: 'audio/wav'));
  }

  Future<Directory> _ttsOutputDir() async {
    final documents = await getApplicationDocumentsDirectory();
    final dir = Directory('${documents.path}/AgenSenseGuiLite/tts');
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> _revealLast() async {
    final path = _lastFile;
    if (path == null || !Platform.isMacOS) {
      return;
    }
    await Process.run('open', ['-R', path]);
  }

  @override
  Widget build(BuildContext context) {
    return SinglePaneTab(
      children: [
        SectionTitle(
          icon: Icons.graphic_eq_outlined,
          title: 'TTS direct test',
          subtitle:
              'Calls /v1/tts/synthesize and converts PCM output to WAV for playback.',
        ),
        field(_text, 'Text', Icons.text_fields_outlined, maxLines: 4),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _synthesize,
              icon: const Icon(Icons.volume_up_outlined),
              label: const Text('Synthesize + play'),
            ),
            OutlinedButton.icon(
              onPressed: _lastFile == null ? null : _playLast,
              icon: const Icon(Icons.replay_outlined),
              label: const Text('Replay'),
            ),
            OutlinedButton.icon(
              onPressed: _lastFile == null || !Platform.isMacOS
                  ? null
                  : _revealLast,
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Reveal WAV'),
            ),
          ],
        ),
        if (_busy) const LinearProgressIndicator(),
        LogPanel(text: _output),
      ],
    );
  }
}

class VoiceWSTab extends StatefulWidget {
  const VoiceWSTab({super.key, required this.config, required this.shared});

  final AppConfig Function() config;
  final SharedTestContext shared;

  @override
  State<VoiceWSTab> createState() => _VoiceWSTabState();
}

class _VoiceAudioSegment {
  const _VoiceAudioSegment({
    required this.streamId,
    required this.audio,
    required this.codec,
    required this.sampleRateHz,
    required this.channels,
  });

  final String streamId;
  final Uint8List audio;
  final String codec;
  final int sampleRateHz;
  final int channels;
}

class _VoiceWSTabState extends State<VoiceWSTab> {
  static const _echoGuardCooldown = Duration(milliseconds: 450);
  static const _vadAutoStopDelay = Duration(milliseconds: 800);
  static const _continuousRestartDelay = Duration(milliseconds: 250);

  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  final _language = TextEditingController(text: 'auto');
  IOWebSocketChannel? _channel;
  StreamSubscription? _socketSub;
  StreamSubscription<Uint8List>? _recordSub;
  Timer? _vadAutoStopTimer;
  BytesBuilder _ttsAudio = BytesBuilder(copy: false);
  final List<_VoiceAudioSegment> _voicePlaybackQueue = <_VoiceAudioSegment>[];
  bool _connected = false;
  bool _recording = false;
  bool _autoRespond = true;
  bool _autoPlay = true;
  bool _continuousTurns = true;
  bool _continuousActive = false;
  bool _restartPending = false;
  bool _echoGuard = false;
  bool _voicePlaying = false;
  bool _playbackGate = false;
  int _seq = 0;
  int _inputStreamSeq = 0;
  int _ttsBytes = 0;
  int _ttsSegmentBytes = 0;
  int _ttsSegmentCount = 0;
  int _ttsSampleRateHz = 16000;
  int _ttsChannels = 1;
  String _ttsCodec = 'pcm_s16le';
  String? _ttsStreamId;
  String? _activeInputStreamId;
  int _voicePlaybackGeneration = 0;
  String _finalASR = '';
  String _llmText = '';
  String _turnStatus = 'Idle';
  String? _voiceWavFile;
  final List<String> _events = <String>[
    'Connect, record, stop, then watch streamed events.',
  ];

  @override
  void dispose() {
    _vadAutoStopTimer?.cancel();
    _closeSocket();
    unawaited(_recordSub?.cancel());
    unawaited(_recorder.dispose());
    unawaited(_player.dispose());
    _language.dispose();
    super.dispose();
  }

  bool get _inputBlockedByPlayback =>
      _echoGuard &&
      (_voicePlaying || _playbackGate || _voicePlaybackQueue.isNotEmpty);

  Future<bool> _connect() async {
    try {
      final config = widget.config();
      final uri = wsUri(config.normalizedBaseUrl, '/v1/voice/ws');
      final channel = IOWebSocketChannel.connect(
        uri,
        headers: {'authorization': 'Bearer ${config.apiKey.trim()}'},
        pingInterval: const Duration(seconds: 20),
        connectTimeout: const Duration(seconds: 15),
      );
      await channel.ready;
      _channel = channel;
      _socketSub = channel.stream.listen(
        _handleSocketEvent,
        onError: (Object error) => _addEvent('socket.error $error'),
        onDone: () {
          if (mounted) {
            setState(() {
              _connected = false;
              _recording = false;
              _turnStatus = 'Disconnected';
            });
          }
          _addEvent('socket.closed');
        },
      );
      setState(() {
        _connected = true;
        _turnStatus = 'Connected';
        _events
          ..clear()
          ..add('connected $uri');
      });
      _sendEvent('session.update', {
        'client_id': config.clientId.trim(),
        'device_label': config.deviceLabel.trim(),
        'session_id': newSessionId('voice'),
        'provider_profile_id': config.providerProfileId.trim(),
        'response_language': _language.text.trim().isEmpty
            ? 'auto'
            : _language.text.trim(),
        'auto_response': _autoRespond,
        'format': audioFormat(config),
        'voice_assistant': {
          'contract': 'universal_voice_layer_v1',
          'ui_context': {
            'current_scene': widget.shared.scene.text.trim().isEmpty
                ? 'voice-ws-validation'
                : widget.shared.scene.text.trim(),
            'client_surface': 'agensense-gui-lite',
          },
          'assistant_intent': {
            'scope': 'mcp',
            'target_id': widget.shared.target.text.trim(),
            'action': widget.shared.action.text.trim(),
            'args': parseJsonObject(widget.shared.args.text),
            'ui_surface': 'voice-ws-validation',
            'label': 'Voice WS shared prompt validation',
          },
          'metadata': {
            'shared_system_prompt': widget.shared.systemPrompt.text.trim(),
            'mcp_servers': parseJsonObject(widget.shared.mcpServers.text),
          },
        },
      });
      return true;
    } catch (error) {
      _addEvent('connect.failed $error');
      return false;
    }
  }

  Future<void> _startFullTurn() async {
    if (!_connected) {
      final connected = await _connect();
      if (!connected) {
        return;
      }
    }
    _continuousActive = _continuousTurns;
    await _startAudio(resetSession: true, activateContinuous: false);
  }

  Future<void> _startAudio({
    bool resetSession = true,
    bool activateContinuous = true,
  }) async {
    if (_channel == null) {
      _addEvent('not connected');
      return;
    }
    if (_recording) {
      return;
    }
    if (_inputBlockedByPlayback) {
      setState(() => _turnStatus = 'Playback active; mic is gated');
      _addEvent('recording.blocked echo_guard');
      return;
    }
    try {
      if (!await _recorder.hasPermission()) {
        _addEvent('microphone permission denied');
        return;
      }
      final config = widget.config();
      _seq = 0;
      _vadAutoStopTimer?.cancel();
      _restartPending = false;
      if (activateContinuous) {
        _continuousActive = _continuousTurns;
      }
      final streamID =
          'input-${(++_inputStreamSeq).toString().padLeft(3, '0')}';
      _activeInputStreamId = streamID;
      if (resetSession) {
        _finalASR = '';
        _llmText = '';
        _ttsBytes = 0;
        _ttsSegmentBytes = 0;
        _ttsSegmentCount = 0;
        _voiceWavFile = null;
        _voicePlaybackGeneration++;
        _voicePlaybackQueue.clear();
        await _player.stop();
      }
      _turnStatus = 'Recording user audio';
      _ttsAudio = BytesBuilder(copy: false);
      _sendEvent('audio.start', {
        'stream_id': streamID,
        'codec': 'pcm_s16le',
        'sample_rate_hz': config.sampleRateHz,
        'channels': config.channels,
      });
      final stream = await _recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: config.sampleRateHz,
          numChannels: config.channels,
          streamBufferSize: 3200,
        ),
      );
      _recordSub = stream.listen((chunk) {
        if (_inputBlockedByPlayback) {
          unawaited(_cancelInputForPlayback('playback gate'));
          return;
        }
        _seq++;
        _channel?.sink.add(chunk);
        if (mounted) {
          setState(() {});
        }
      });
      setState(() => _recording = true);
      _addEvent('recording.started $streamID');
    } catch (error) {
      _addEvent('recording.failed $error');
    }
  }

  Future<void> _stopAudio({
    bool manual = false,
    bool restartAfterResponse = false,
  }) async {
    try {
      _vadAutoStopTimer?.cancel();
      if (manual) {
        _continuousActive = false;
        _restartPending = false;
      }
      final streamID = _activeInputStreamId;
      if (!_recording || streamID == null) {
        if (mounted) {
          setState(() {
            _recording = false;
            _turnStatus = manual ? 'Stopped' : _turnStatus;
          });
        }
        return;
      }
      await _recorder.stop();
      await _recordSub?.cancel();
      _recordSub = null;
      _sendEvent('audio.stop', {'stream_id': streamID, 'last_seq': _seq});
      setState(() {
        _recording = false;
        _activeInputStreamId = null;
        _turnStatus = restartAfterResponse
            ? 'Turn submitted; waiting for response'
            : 'Waiting for ASR final';
      });
      _addEvent('recording.stopped $streamID $_seq frames');
    } catch (error) {
      _addEvent('stop.failed $error');
    }
  }

  Future<void> _stopListening() async {
    _continuousActive = false;
    _restartPending = false;
    await _stopAudio(manual: true);
  }

  Future<void> stopForTabSwitch() async {
    _continuousActive = false;
    _restartPending = false;
    _vadAutoStopTimer?.cancel();
    if (_recording) {
      await _recordSub?.cancel();
      _recordSub = null;
      await _recorder.stop();
      _sendEvent('input.cancel', {});
    }
    if (mounted) {
      setState(() {
        _recording = false;
        _activeInputStreamId = null;
        _turnStatus = 'Stopped on tab switch';
      });
    }
    _addEvent('recording.stopped tab_switch');
  }

  Future<void> _disconnect() async {
    _continuousActive = false;
    _restartPending = false;
    _vadAutoStopTimer?.cancel();
    await _recordSub?.cancel();
    if (_recording) {
      await _recorder.stop();
    }
    _voicePlaybackGeneration++;
    _voicePlaybackQueue.clear();
    await _player.stop();
    await _closeSocket();
    if (mounted) {
      setState(() {
        _connected = false;
        _recording = false;
        _turnStatus = 'Disconnected';
      });
    }
  }

  Future<void> _cancelInputForPlayback(String reason) async {
    if (!_echoGuard || !_recording) {
      return;
    }
    try {
      _vadAutoStopTimer?.cancel();
      await _recordSub?.cancel();
      _recordSub = null;
      await _recorder.stop();
      _sendEvent('input.cancel', {});
      if (mounted) {
        setState(() {
          _recording = false;
          _turnStatus = 'Mic gated during playback';
        });
      }
      _addEvent('recording.cancelled_for_playback $reason');
    } catch (error) {
      _addEvent('recording.cancel_for_playback.failed $error');
    }
  }

  Future<void> _closeSocket() async {
    await _socketSub?.cancel();
    _socketSub = null;
    await _channel?.sink.close();
    _channel = null;
  }

  void _handleSocketEvent(Object? event) {
    if (event is String) {
      final decoded = jsonDecode(event) as Map<String, dynamic>;
      final type = stringValue(decoded['type']);
      final payload = asMap(decoded['payload']);
      if (type == 'session.ready') {
        _turnStatus = 'Session ready';
      }
      if (type == 'vad.state') {
        _handleVADState(stringValue(payload['state']));
      }
      if (type == 'asr.final') {
        _finalASR = stringValue(payload['text']);
        _turnStatus = _finalASR.trim().isEmpty
            ? 'ASR final was empty'
            : _autoRespond
            ? 'ASR final received; server is requesting LLM/TTS'
            : 'ASR final received';
      }
      if (type == 'llm.delta') {
        _llmText += stringValue(payload['text']);
        _turnStatus = 'LLM streaming';
      }
      if (type == 'tts.start') {
        _ttsAudio = BytesBuilder(copy: false);
        _ttsSegmentBytes = 0;
        _ttsStreamId = stringValue(payload['stream_id']);
        _ttsCodec = stringValue(payload['codec'], fallback: 'pcm_s16le');
        _ttsSampleRateHz = intValue(payload['sample_rate_hz'], fallback: 16000);
        _ttsChannels = intValue(payload['channels'], fallback: 1);
        _turnStatus = 'TTS segment streaming';
      }
      if (type == 'tts.stop' && _ttsSegmentBytes > 0) {
        final audio = _ttsAudio.toBytes();
        _ttsAudio = BytesBuilder(copy: false);
        _ttsSegmentCount++;
        _ttsSegmentBytes = 0;
        if (_autoPlay) {
          _voicePlaybackQueue.add(
            _VoiceAudioSegment(
              streamId: _ttsStreamId ?? 'tts-$_ttsSegmentCount',
              audio: audio,
              codec: looksLikeWav(audio) ? 'wav' : _ttsCodec,
              sampleRateHz: _ttsSampleRateHz,
              channels: _ttsChannels,
            ),
          );
          _turnStatus = _voicePlaying
              ? 'TTS segment queued'
              : 'TTS segment received; starting playback';
          unawaited(
            _drainVoicePlaybackQueue().catchError((Object error) {
              _addEvent('voice.playback.failed $error');
              if (mounted) {
                setState(() => _turnStatus = 'TTS playback failed');
              }
            }),
          );
        }
      }
      if (type == 'response.done') {
        final status = stringValue(payload['status'], fallback: 'done');
        _turnStatus = _voicePlaying || _voicePlaybackQueue.isNotEmpty
            ? 'Response $status; playing audio'
            : 'Response $status';
        if (_continuousActive && _continuousTurns && !_recording) {
          _scheduleContinuousRestart();
        }
      }
      _addEvent('recv $type ${payload.isEmpty ? '' : compact(payload)}');
      return;
    }
    if (event is List<int>) {
      final bytes = Uint8List.fromList(event);
      _ttsAudio.add(bytes);
      _ttsBytes += bytes.length;
      _ttsSegmentBytes += bytes.length;
      _addEvent('recv binary ${bytes.length} bytes');
      return;
    }
    _addEvent('recv ${event.runtimeType}');
  }

  void _handleVADState(String state) {
    if (state == 'speech_started') {
      _vadAutoStopTimer?.cancel();
      if (_recording) {
        _turnStatus = 'Speech detected';
      }
      return;
    }
    if (state != 'speech_stopped' || !_continuousTurns || !_recording) {
      return;
    }
    _turnStatus = 'Silence detected; submitting turn';
    _vadAutoStopTimer?.cancel();
    _vadAutoStopTimer = Timer(_vadAutoStopDelay, () {
      if (!mounted || !_recording || _inputBlockedByPlayback) {
        return;
      }
      _addEvent('recording.submit vad_silence');
      unawaited(
        _stopAudio(restartAfterResponse: _continuousActive && _continuousTurns),
      );
    });
  }

  void _scheduleContinuousRestart({String reason = 'continuous'}) {
    if (_restartPending) {
      return;
    }
    _restartPending = true;
    if (mounted) {
      setState(() => _turnStatus = 'Response done; listening will resume');
    } else {
      _turnStatus = 'Response done; listening will resume';
    }
    Future<void>.delayed(_continuousRestartDelay, () async {
      if (!mounted ||
          !_continuousActive ||
          !_continuousTurns ||
          _recording ||
          !_connected ||
          _inputBlockedByPlayback) {
        _restartPending = false;
        return;
      }
      _addEvent('recording.restart $reason');
      await _startAudio(resetSession: false, activateContinuous: false);
    });
  }

  Future<void> _drainVoicePlaybackQueue() async {
    if (_voicePlaying) {
      return;
    }
    if (mounted) {
      setState(() {
        _voicePlaying = true;
        _playbackGate = _echoGuard;
      });
    } else {
      _voicePlaying = true;
      _playbackGate = _echoGuard;
    }
    final generation = _voicePlaybackGeneration;
    await _cancelInputForPlayback('tts playback');
    try {
      while (mounted &&
          generation == _voicePlaybackGeneration &&
          _voicePlaybackQueue.isNotEmpty) {
        final segment = _voicePlaybackQueue.removeAt(0);
        await _playVoiceSegment(segment, generation);
      }
    } finally {
      if (_echoGuard) {
        await Future<void>.delayed(_echoGuardCooldown);
      }
      _voicePlaying = false;
      _playbackGate = false;
      final shouldResumeListening =
          generation == _voicePlaybackGeneration &&
          _voicePlaybackQueue.isEmpty &&
          _continuousActive &&
          _continuousTurns &&
          !_recording &&
          _connected;
      if (mounted && generation == _voicePlaybackGeneration) {
        setState(() {
          if (_voicePlaybackQueue.isEmpty && !_recording) {
            _turnStatus = shouldResumeListening
                ? 'Playback complete; listening will resume'
                : 'Complete';
          }
        });
      }
      if (shouldResumeListening) {
        _scheduleContinuousRestart(reason: 'after_playback_gate');
      }
    }
  }

  Future<void> _playVoiceSegment(
    _VoiceAudioSegment segment,
    int generation,
  ) async {
    final wav = ensureWavAudio(
      audio: segment.audio,
      codec: segment.codec,
      sampleRateHz: segment.sampleRateHz,
      channels: segment.channels,
    );
    final dir = await _voiceOutputDir();
    final file = File(
      '${dir.path}/agensense_voice_${DateTime.now().millisecondsSinceEpoch}_${segment.streamId}.wav',
    );
    await file.writeAsBytes(wav, flush: true);
    final exists = await file.exists();
    final length = exists ? await file.length() : 0;
    if (!exists || length <= 0) {
      throw FileSystemException(
        'Voice TTS WAV write verification failed',
        file.path,
      );
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _voiceWavFile = file.path;
      _turnStatus = 'Playing ${segment.streamId}';
    });
    if (generation != _voicePlaybackGeneration) {
      return;
    }
    await _player.play(DeviceFileSource(file.path, mimeType: 'audio/wav'));
    await _waitForPlaybackComplete(segment);
    _addEvent('voice.played $length bytes ${file.path}');
  }

  Future<void> _waitForPlaybackComplete(_VoiceAudioSegment segment) async {
    final bytesPerSecond = segment.sampleRateHz * segment.channels * 2;
    final audioMS = bytesPerSecond > 0
        ? (segment.audio.length * 1000 / bytesPerSecond).ceil()
        : 5000;
    final timeout = Duration(
      milliseconds: audioMS.clamp(3000, 60000).toInt() + 1500,
    );
    await _player.onPlayerComplete.first.timeout(timeout, onTimeout: () {});
  }

  Future<Directory> _voiceOutputDir() async {
    final documents = await getApplicationDocumentsDirectory();
    final dir = Directory('${documents.path}/AgenSenseGuiLite/voice');
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> _replayVoiceAudio() async {
    final path = _voiceWavFile;
    if (path == null) {
      return;
    }
    final file = File(path);
    if (!await file.exists()) {
      _addEvent('voice.replay.missing $path');
      return;
    }
    await _cancelInputForPlayback('tts replay');
    await _player.stop();
    if (mounted && _echoGuard) {
      setState(() => _playbackGate = true);
    }
    try {
      await _player.play(DeviceFileSource(path, mimeType: 'audio/wav'));
      await _player.onPlayerComplete.first.timeout(
        const Duration(seconds: 60),
        onTimeout: () {},
      );
      if (_echoGuard) {
        await Future<void>.delayed(_echoGuardCooldown);
      }
    } finally {
      if (mounted) {
        setState(() => _playbackGate = false);
      }
    }
  }

  Future<void> _revealVoiceAudio() async {
    final path = _voiceWavFile;
    if (path == null || !Platform.isMacOS) {
      return;
    }
    await Process.run('open', ['-R', path]);
  }

  void _sendEvent(String type, Map<String, dynamic> payload) {
    final message = {
      'type': type,
      'request_id': 'gui-${DateTime.now().millisecondsSinceEpoch}',
      'payload': payload,
    };
    _channel?.sink.add(jsonEncode(message));
    _addEvent('send $type ${compact(payload)}');
  }

  void _addEvent(String line) {
    if (!mounted) {
      return;
    }
    setState(() {
      final time = TimeOfDay.now().format(context);
      _events.insert(0, '$time  $line');
      if (_events.length > 160) {
        _events.removeLast();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return TwoPaneTab(
      left: [
        SectionTitle(
          icon: Icons.settings_voice_outlined,
          title: 'Realtime voice WebSocket',
          subtitle:
              'Streams live PCM frames to /v1/voice/ws and plays returned TTS audio.',
        ),
        field(
          _language,
          'Response language: auto, zh-Hans, zh-Hant, en',
          Icons.language_outlined,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _autoRespond,
          title: const Text('Server auto-respond after asr.final'),
          onChanged: (value) => setState(() => _autoRespond = value),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _autoPlay,
          title: const Text('Auto-play TTS binary stream'),
          onChanged: (value) => setState(() => _autoPlay = value),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _continuousTurns,
          title: const Text('Continuous VAD turns'),
          onChanged: (value) => setState(() => _continuousTurns = value),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _echoGuard,
          title: const Text('Mic gate during TTS playback'),
          onChanged: (value) => setState(() => _echoGuard = value),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed:
                  _recording || _continuousActive || _inputBlockedByPlayback
                  ? null
                  : _startFullTurn,
              icon: Icon(_connected ? Icons.mic_outlined : Icons.play_arrow),
              label: Text(_connected ? 'Start continuous' : 'Connect + listen'),
            ),
            OutlinedButton.icon(
              onPressed: _connected ? null : _connect,
              icon: const Icon(Icons.link_outlined),
              label: const Text('Connect'),
            ),
            OutlinedButton.icon(
              onPressed:
                  _connected &&
                      !_recording &&
                      !_continuousActive &&
                      !_inputBlockedByPlayback
                  ? _startAudio
                  : null,
              icon: const Icon(Icons.mic_outlined),
              label: const Text('Record'),
            ),
            FilledButton.tonalIcon(
              onPressed: _recording || _continuousActive || _restartPending
                  ? _stopListening
                  : null,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('Stop'),
            ),
            OutlinedButton.icon(
              onPressed: _connected ? _disconnect : null,
              icon: const Icon(Icons.link_off_outlined),
              label: const Text('Disconnect'),
            ),
            OutlinedButton.icon(
              onPressed: _voiceWavFile == null || _voicePlaying
                  ? null
                  : _replayVoiceAudio,
              icon: const Icon(Icons.replay_outlined),
              label: const Text('Replay TTS'),
            ),
            OutlinedButton.icon(
              onPressed: _voiceWavFile == null || !Platform.isMacOS
                  ? null
                  : _revealVoiceAudio,
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Reveal WAV'),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(label: Text(_connected ? 'connected' : 'disconnected')),
            Chip(label: Text(_recording ? 'recording' : 'idle')),
            if (_continuousTurns) const Chip(label: Text('continuous')),
            if (_continuousActive) const Chip(label: Text('listening loop')),
            if (_echoGuard) const Chip(label: Text('echo guard')),
            if (_playbackGate) const Chip(label: Text('mic gated')),
            Chip(label: Text(_turnStatus)),
            Chip(label: Text('frames $_seq')),
            Chip(label: Text('tts $_ttsBytes bytes')),
            Chip(label: Text('segments $_ttsSegmentCount')),
            if (_voicePlaybackQueue.isNotEmpty)
              Chip(label: Text('queue ${_voicePlaybackQueue.length}')),
            if (_voiceWavFile != null) const Chip(label: Text('wav saved')),
          ],
        ),
      ],
      right: [
        SectionTitle(
          icon: Icons.receipt_long_outlined,
          title: 'Event stream',
          subtitle: 'JSON control messages and binary audio frames.',
        ),
        LogPanel(text: _events.join('\n')),
        if (_finalASR.isNotEmpty) ...[
          const SizedBox(height: 12),
          LogPanel(text: _finalASR, title: 'ASR final', height: 96),
        ],
        if (_llmText.isNotEmpty) ...[
          const SizedBox(height: 12),
          LogPanel(text: _llmText, title: 'LLM text', height: 128),
        ],
      ],
    );
  }
}

class DeviceTab extends StatefulWidget {
  const DeviceTab({super.key, required this.config});

  final AppConfig Function() config;

  @override
  State<DeviceTab> createState() => _DeviceTabState();
}

class _DeviceTabState extends State<DeviceTab> {
  final _deviceId = TextEditingController(text: 'gui-lite-device-001');
  final _chipId = TextEditingController(text: 'flutter-sim');
  final _sku = TextEditingController(text: 'flutter-gui-lite');
  final _firmware = TextEditingController(text: '0.1.0');
  final _channel = TextEditingController(text: 'dev');
  final _claimToken = TextEditingController();
  final _capabilities = TextEditingController(
    text:
        '{\n  "display": "gui",\n  "touch": true,\n  "usb_hid": false,\n  "usb_mic": true\n}',
  );

  bool _busy = false;
  String _deviceToken = '';
  String _sessionWsUrl = '';
  String _output = 'Bootstrap a simulated hardware client.';

  @override
  void dispose() {
    _deviceId.dispose();
    _chipId.dispose();
    _sku.dispose();
    _firmware.dispose();
    _channel.dispose();
    _claimToken.dispose();
    _capabilities.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _run(() async {
      final response = await AgenSenseApi(widget.config()).bootstrap({
        'device_id': _deviceId.text.trim(),
        'chip_id': _chipId.text.trim(),
        'hardware_sku': _sku.text.trim(),
        'firmware_version': _firmware.text.trim(),
        'firmware_channel': _channel.text.trim(),
        'claim_token': _claimToken.text.trim(),
        'capabilities': parseJsonObject(_capabilities.text),
      });
      _deviceToken = stringValue(response['device_token']);
      _sessionWsUrl = stringValue(response['ws_url']);
      setState(() => _output = prettyJson(response));
    });
  }

  Future<void> _config() async {
    if (_deviceToken.isEmpty) {
      setState(() => _output = 'Bootstrap first to obtain a device token.');
      return;
    }
    await _run(() async {
      final response = await AgenSenseApi(
        widget.config(),
      ).deviceConfig(deviceId: _deviceId.text.trim(), token: _deviceToken);
      setState(() => _output = prettyJson(response));
    });
  }

  Future<void> _telemetry() async {
    if (_deviceToken.isEmpty) {
      setState(() => _output = 'Bootstrap first to obtain a device token.');
      return;
    }
    await _run(() async {
      final response = await AgenSenseApi(widget.config()).sendTelemetry(
        deviceId: _deviceId.text.trim(),
        token: _deviceToken,
        telemetry: {
          'source': 'agensense-gui-lite',
          'battery': 100,
          'rssi': -42,
          'at': DateTime.now().toIso8601String(),
        },
      );
      setState(() => _output = prettyJson(response));
    });
  }

  Future<void> _sessionHello() async {
    if (_deviceToken.isEmpty) {
      setState(() => _output = 'Bootstrap first to obtain a device token.');
      return;
    }
    await _run(() async {
      final config = widget.config();
      final uri = _sessionWsUrl.trim().isNotEmpty
          ? Uri.parse(_sessionWsUrl.trim())
          : wsUri(config.normalizedBaseUrl, '/v1/session/ws');
      final channel = IOWebSocketChannel.connect(
        uri,
        headers: {
          'authorization': 'Bearer $_deviceToken',
          'x-device-id': _deviceId.text.trim(),
          'x-protocol-version': 'v1',
        },
        connectTimeout: const Duration(seconds: 15),
      );
      await channel.ready;
      channel.sink.add(
        jsonEncode({
          'type': 'hello',
          'request_id': 'gui-${DateTime.now().millisecondsSinceEpoch}',
          'payload': {
            'device': {
              'device_id': _deviceId.text.trim(),
              'hardware_sku': _sku.text.trim(),
              'firmware_version': _firmware.text.trim(),
              'capabilities': parseJsonObject(_capabilities.text),
            },
            'state': {'config_version': 0},
          },
        }),
      );
      final firstEvent = await channel.stream.first.timeout(
        const Duration(seconds: 10),
      );
      await channel.sink.close();
      setState(() {
        _output = prettyJson({
          'ws_url': uri.toString(),
          'first_event': firstEvent is String
              ? jsonDecode(firstEvent)
              : firstEvent,
        });
      });
    });
  }

  Future<void> _run(Future<void> Function() task) async {
    setState(() => _busy = true);
    try {
      await task();
    } catch (error) {
      if (mounted) {
        setState(() => _output = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return TwoPaneTab(
      left: [
        SectionTitle(
          icon: Icons.developer_board_outlined,
          title: 'Device compatibility',
          subtitle:
              'Validates /v1/bootstrap, /v1/device/config, and telemetry.',
        ),
        field(_deviceId, 'Device ID', Icons.memory_outlined),
        field(_chipId, 'Chip ID', Icons.developer_board_outlined),
        field(_sku, 'Hardware SKU', Icons.category_outlined),
        field(_firmware, 'Firmware version', Icons.new_releases_outlined),
        field(_channel, 'Firmware channel', Icons.alt_route_outlined),
        field(_claimToken, 'Claim token', Icons.lock_open_outlined),
        field(
          _capabilities,
          'Capabilities JSON',
          Icons.data_object_outlined,
          maxLines: 6,
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _bootstrap,
              icon: const Icon(Icons.rocket_launch_outlined),
              label: const Text('Bootstrap'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _config,
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Get config'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _telemetry,
              icon: const Icon(Icons.sensors_outlined),
              label: const Text('Telemetry'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _sessionHello,
              icon: const Icon(Icons.cable_outlined),
              label: const Text('WS hello'),
            ),
          ],
        ),
      ],
      right: [
        SectionTitle(
          icon: Icons.terminal_outlined,
          title: 'Device output',
          subtitle: 'Device token is kept only in this running UI state.',
        ),
        if (_busy) const LinearProgressIndicator(),
        LogPanel(text: _output),
      ],
    );
  }
}

class DebugTab extends StatefulWidget {
  const DebugTab({super.key, required this.config});

  final AppConfig Function() config;

  @override
  State<DebugTab> createState() => _DebugTabState();
}

class _DebugTabState extends State<DebugTab> {
  bool _busy = false;
  List<Map<String, dynamic>> _traces = const <Map<String, dynamic>>[];
  String _output =
      'Enable AGENSENSE_DEBUG=true on the server, then list traces.';

  Future<void> _listTraces() async {
    setState(() => _busy = true);
    try {
      final traces = await AgenSenseApi(widget.config()).traces();
      if (!mounted) {
        return;
      }
      setState(() {
        _traces = traces;
        _output = prettyJson({'count': traces.length, 'items': traces});
      });
    } catch (error) {
      if (mounted) {
        setState(() => _output = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return TwoPaneTab(
      left: [
        SectionTitle(
          icon: Icons.bug_report_outlined,
          title: 'Debug traces',
          subtitle: 'Reads /debug/api/traces when debug mode is enabled.',
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _listTraces,
          icon: const Icon(Icons.refresh_outlined),
          label: const Text('List traces'),
        ),
        if (_busy) const LinearProgressIndicator(),
        ..._traces.take(12).map((trace) {
          final title = stringValue(trace['id'], fallback: 'trace');
          final subtitle = [
            stringValue(trace['kind']),
            stringValue(trace['status']),
            stringValue(trace['client_id']),
          ].where((item) => item.isNotEmpty).join(' · ');
          return ListTile(
            dense: true,
            leading: const Icon(Icons.timeline_outlined),
            title: Text(title),
            subtitle: Text(subtitle),
            onTap: () => setState(() => _output = prettyJson(trace)),
          );
        }),
      ],
      right: [
        SectionTitle(
          icon: Icons.article_outlined,
          title: 'Trace JSON',
          subtitle: 'Asset URLs are relative to the AgenSense base URL.',
        ),
        LogPanel(text: _output),
      ],
    );
  }
}

class TwoPaneTab extends StatelessWidget {
  const TwoPaneTab({super.key, required this.left, required this.right});

  final List<Widget> left;
  final List<Widget> right;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 900;
        final leftPane = Panel(children: left);
        final rightPane = Panel(children: right);
        if (narrow) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [leftPane, const SizedBox(height: 16), rightPane],
          );
        }
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 420, child: leftPane),
              const SizedBox(width: 16),
              Expanded(child: rightPane),
            ],
          ),
        );
      },
    );
  }
}

class SinglePaneTab extends StatelessWidget {
  const SinglePaneTab({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [Panel(children: children)],
    );
  }
}

class Panel extends StatelessWidget {
  const Panel({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: withSpacing(children, 12),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class ProviderProfileTile extends StatelessWidget {
  const ProviderProfileTile({super.key, required this.profile});

  final ProviderProfile profile;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      if (profile.name.isNotEmpty) profile.name,
      if (profile.llmModel.isNotEmpty) 'LLM ${profile.llmModel}',
      if (profile.asrModel.isNotEmpty) 'ASR ${profile.asrModel}',
      if (profile.ttsModel.isNotEmpty) 'TTS ${profile.ttsModel}',
    ].join(' · ');
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        profile.isDefault ? Icons.star_outlined : Icons.hub_outlined,
        color: profile.isDefault ? const Color(0xffb87b00) : null,
      ),
      title: Text(profile.id),
      subtitle: Text(subtitle.isEmpty ? profile.namespace : subtitle),
    );
  }
}

class LogPanel extends StatefulWidget {
  const LogPanel({
    super.key,
    required this.text,
    this.title = 'Output',
    this.height = 220,
  });

  final String text;
  final String title;
  final double height;

  @override
  State<LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<LogPanel> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: widget.height,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xff101816),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: const TextStyle(
                color: Color(0xffb7cbc5),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: SelectableText(
                    widget.text,
                    style: const TextStyle(
                      color: Color(0xffedf8f3),
                      fontFamily: 'monospace',
                      fontSize: 12.5,
                      height: 1.38,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget field(
  TextEditingController controller,
  String label,
  IconData icon, {
  bool obscure = false,
  int maxLines = 1,
}) {
  if (!obscure && maxLines > 1) {
    return FixedTextArea(
      controller: controller,
      label: label,
      icon: icon,
      lines: maxLines,
    );
  }
  return TextField(
    controller: controller,
    obscureText: obscure,
    maxLines: 1,
    decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
  );
}

class FixedTextArea extends StatefulWidget {
  const FixedTextArea({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    required this.lines,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final int lines;

  @override
  State<FixedTextArea> createState() => _FixedTextAreaState();
}

class _FixedTextAreaState extends State<FixedTextArea> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42 + widget.lines * 22,
      child: Scrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        child: TextField(
          controller: widget.controller,
          scrollController: _scrollController,
          expands: true,
          maxLines: null,
          minLines: null,
          keyboardType: TextInputType.multiline,
          textAlignVertical: TextAlignVertical.top,
          decoration: InputDecoration(
            labelText: widget.label,
            prefixIcon: Icon(widget.icon),
          ),
        ),
      ),
    );
  }
}

List<Widget> withSpacing(List<Widget> children, double spacing) {
  final out = <Widget>[];
  for (var index = 0; index < children.length; index++) {
    if (index > 0) {
      out.add(SizedBox(height: spacing));
    }
    out.add(children[index]);
  }
  return out;
}

Map<String, dynamic> parseJsonObject(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return <String, dynamic>{};
  }
  final value = jsonDecode(trimmed);
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, val) => MapEntry(key.toString(), val));
  }
  throw const FormatException('Expected a JSON object.');
}

String prettyJson(Object? value) {
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } catch (_) {
    return value.toString();
  }
}

String compact(Object? value) {
  final text = jsonEncode(value);
  if (text.length <= 180) {
    return text;
  }
  return '${text.substring(0, 180)}...';
}

Uri wsUri(String baseUrl, String path) {
  final uri = Uri.parse('$baseUrl$path');
  final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
  return uri.replace(scheme: scheme);
}
