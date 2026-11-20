part of 'vigil_inspector.dart';

class _DebugSession {
  const _DebugSession({
    required this.name,
    required this.notes,
    required this.createdAt,
    required this.calls,
  });

  final String name;
  final String notes;
  final DateTime createdAt;
  final List<VigilHttpCall> calls;

  Map<String, Object?> toJson() => {
        'format': 'vigil-debug-session',
        'version': 1,
        'name': name,
        'notes': notes,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'calls': calls.map(VigilCallCodec.callToJson).toList(),
      };

  factory _DebugSession.fromJson(Object? value) {
    if (value is! Map ||
        value['format'] != 'vigil-debug-session' ||
        value['version'] != 1) {
      throw const FormatException('Unsupported session format.');
    }
    final name = value['name'] as String;
    final notes = value['notes'] as String;
    final calls = value['calls'] as List;
    if (name.trim().isEmpty || calls.isEmpty) {
      throw const FormatException(
          'A session needs a name and at least one request.');
    }
    final decoded = List<VigilHttpCall>.unmodifiable(
      calls.map((value) =>
          VigilCallCodec.callFromJson(value as Map<String, dynamic>)),
    );
    if (decoded.map((call) => call.id).toSet().length != decoded.length) {
      throw const FormatException('Duplicate request IDs.');
    }
    return _DebugSession(
      name: name,
      notes: notes,
      createdAt: DateTime.parse(value['createdAt'] as String),
      calls: decoded,
    );
  }
}

class _SessionsPage extends StatefulWidget {
  const _SessionsPage({required this.vigil});

  final Vigil vigil;

  @override
  State<_SessionsPage> createState() => _SessionsPageState();
}

class _SessionsPageState extends State<_SessionsPage> {
  static const _storageKey = 'vigil.debug_sessions.v1';
  static const _maxBytes = 4 * 1024 * 1024;
  final _storage = SharedPreferencesAsync();
  List<_DebugSession>? _sessions;
  bool _saving = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await _storage.getString(_storageKey);
      final sessions = raw == null
          ? <_DebugSession>[]
          : (jsonDecode(raw) as List).map(_DebugSession.fromJson).toList();
      if (mounted) {
        setState(() {
          _sessions = sessions;
          _loadError = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadError = 'Unable to read saved sessions.');
      }
    }
  }

  Future<void> _write(List<_DebugSession> sessions) async {
    setState(() => _saving = true);
    try {
      final json =
          jsonEncode(sessions.map((session) => session.toJson()).toList());
      if (utf8.encode(json).length > _maxBytes) {
        throw const FormatException(
            'Session storage is full. Delete a session or save fewer calls.');
      }
      await _storage.setString(_storageKey, json);
      if (mounted) setState(() => _sessions = sessions);
    } catch (error) {
      if (mounted) {
        _message(error is FormatException
            ? error.message
            : 'Unable to save sessions.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final sessions = _sessions;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug sessions'),
        actions: [
          IconButton(
            tooltip: 'Import session from clipboard',
            onPressed: sessions == null || _saving ? null : _import,
            icon: const Icon(Icons.content_paste),
          ),
        ],
      ),
      body: sessions == null
          ? Center(
              child: _loadError == null
                  ? const CircularProgressIndicator()
                  : TextButton(
                      onPressed: _load, child: Text('$_loadError Retry')))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save current capture'),
                ),
                if (sessions.isEmpty)
                  const ListTile(title: Text('No saved sessions')),
                for (final session in sessions)
                  ListTile(
                    title: Text(session.name),
                    subtitle: Text(
                        '${session.calls.length} requests · ${session.createdAt.toLocal().toString().split('.').first}'),
                    onTap: () =>
                        Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => _SessionDetailPage(session, widget.vigil),
                    )),
                    trailing: IconButton(
                      tooltip: 'Delete session',
                      onPressed: _saving ? null : () => _delete(session),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _save() async {
    final calls = widget.vigil.calls
        .where((call) => call.state != VigilCallState.pending)
        .toList();
    if (calls.isEmpty) {
      _message('Make a request before saving a session.');
      return;
    }
    final details = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const _SessionNameDialog(),
    );
    if (!mounted || details == null || _saving) return;
    await _write([
      _DebugSession(
          name: details.$1,
          notes: details.$2,
          createdAt: DateTime.now(),
          calls: calls),
      ..._sessions!,
    ]);
  }

  Future<void> _import() async {
    try {
      final raw = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      if (!mounted || _saving) return;
      if (raw == null || raw.length > _maxBytes) throw const FormatException();
      await _write([_DebugSession.fromJson(jsonDecode(raw)), ..._sessions!]);
    } catch (_) {
      if (mounted) {
        _message('Clipboard does not contain a valid Vigil session.');
      }
    }
  }

  Future<void> _delete(_DebugSession session) async {
    final delete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete saved session?'),
        content: Text(session.name),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (!mounted || delete != true || _saving) return;
    await _write(_sessions!.where((item) => item != session).toList());
  }
}

class _SessionNameDialog extends StatefulWidget {
  const _SessionNameDialog();

  @override
  State<_SessionNameDialog> createState() => _SessionNameDialogState();
}

class _SessionNameDialogState extends State<_SessionNameDialog> {
  final _name = TextEditingController();
  final _notes = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Save debug session'),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              autofocus: true,
              controller: _name,
              maxLength: 100,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Session name'),
            ),
            TextField(
              controller: _notes,
              maxLength: 1000,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: _name.text.trim().isEmpty
                ? null
                : () => Navigator.pop(
                    context, (_name.text.trim(), _notes.text.trim())),
            child: const Text('Save'),
          ),
        ],
      );
}

class _SessionDetailPage extends StatelessWidget {
  const _SessionDetailPage(this.session, this.vigil);

  final _DebugSession session;
  final Vigil vigil;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(session.name),
          actions: [
            IconButton(
              tooltip: 'Copy session JSON',
              onPressed: () => _copyWithFeedback(
                  context, jsonEncode(session.toJson()), 'Session copied'),
              icon: const Icon(Icons.copy),
            ),
          ],
        ),
        body: ListView(
          children: [
            if (session.notes.isNotEmpty) ListTile(title: Text(session.notes)),
            for (final call in session.calls.reversed)
              _CallTile(
                call: call,
                selected: false,
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => _InspectorTools(
                    savedCalls: session.calls,
                    child: _CallDetailPage(call: call, vigil: vigil),
                  ),
                )),
              ),
          ],
        ),
      );
}
