part of 'vigil_inspector.dart';

class _InspectorTools extends InheritedWidget {
  const _InspectorTools({
    required super.child,
    this.vigil,
    this.savedCalls,
    this.replay,
  });

  final Vigil? vigil;
  final List<VigilHttpCall>? savedCalls;
  final VigilReplay? replay;

  List<VigilHttpCall> get calls => savedCalls ?? vigil!.calls;

  @override
  bool updateShouldNotify(_InspectorTools oldWidget) => true;
}

class _LiveCallDetail extends StatelessWidget {
  const _LiveCallDetail({required this.call, required this.vigil});

  final VigilHttpCall call;
  final Vigil vigil;

  @override
  Widget build(BuildContext context) => StreamBuilder<VigilEvent>(
        stream: vigil.events,
        builder: (_, __) => _CallDetailPage(
          call: vigil.calls.where((item) => item.id == call.id).firstOrNull ??
              call,
          vigil: vigil,
        ),
      );
}

class _JsonBody extends StatefulWidget {
  const _JsonBody({super.key, required this.text});

  final String text;

  @override
  State<_JsonBody> createState() => _JsonBodyState();
}

class _JsonBodyState extends State<_JsonBody> {
  final _expanded = {r'$'};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final Object? json;
    try {
      json = jsonDecode(widget.text);
    } on FormatException {
      return _CodeBlock(widget.text);
    }
    final root = _JsonNode(r'$', r'$', json);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          decoration: const InputDecoration(
            labelText: 'Search JSON fields or values',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) =>
              setState(() => _query = value.trim().toLowerCase()),
        ),
        const SizedBox(height: 8),
        if (_query.isNotEmpty && !root.matches(_query))
          const _MutedText('No matching JSON fields')
        else
          ..._rows(root, 0),
      ],
    );
  }

  Iterable<Widget> _rows(_JsonNode node, int depth,
      {bool parentMatches = false}) sync* {
    final matchesGroup =
        parentMatches || node.name.toLowerCase().contains(_query);
    final open = _expanded.contains(node.path) || _query.isNotEmpty;
    final children = node.children;
    yield Container(
      margin: EdgeInsets.only(left: (depth * 12).clamp(0, 72).toDouble()),
      padding: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        border: Border(
            left: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          if (children.isNotEmpty)
            IconButton(
              tooltip: open ? 'Collapse ${node.name}' : 'Expand ${node.name}',
              onPressed: _query.isNotEmpty
                  ? null
                  : () => setState(() {
                        if (!_expanded.remove(node.path)) {
                          _expanded.add(node.path);
                        }
                      }),
              icon: Icon(open ? Icons.expand_more : Icons.chevron_right),
            ),
          Expanded(
              child: SelectableText.rich(TextSpan(
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.7,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            children: [
              TextSpan(
                  text: '${node.name}: ',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              TextSpan(
                  text: node.preview,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  )),
            ],
          ))),
          IconButton(
            tooltip: 'Copy JSON path',
            onPressed: () =>
                _copyWithFeedback(context, node.path, 'JSON path copied'),
            icon: const Icon(Icons.content_copy, size: 16),
          ),
        ],
      ),
    );
    if (open) {
      for (final child in children) {
        if (_query.isEmpty || matchesGroup || child.matches(_query)) {
          yield* _rows(child, depth + 1, parentMatches: matchesGroup);
        }
      }
    }
  }
}

class _JsonNode {
  _JsonNode(this.name, this.path, this.value);

  final String name;
  final String path;
  final Object? value;

  late final List<_JsonNode> children = switch (value) {
    final Map<String, dynamic> map => [
        for (final entry in map.entries)
          _JsonNode(entry.key, '$path[${jsonEncode(entry.key)}]', entry.value),
      ],
    final List list => [
        for (var i = 0; i < list.length; i++)
          _JsonNode('[$i]', '$path[$i]', list[i]),
      ],
    _ => const [],
  };

  String get preview => switch (value) {
        final Map map => '{${map.length} fields}',
        final List list => '[${list.length} items]',
        _ => jsonEncode(value),
      };

  bool matches(String query) =>
      name.toLowerCase().contains(query) ||
      (children.isEmpty && preview.toLowerCase().contains(query)) ||
      children.any((child) => child.matches(query));
}

class _AdvancedFilters {
  const _AdvancedFilters({
    this.host = '',
    this.method = '',
    this.minStatus,
    this.maxStatus,
    this.minMs,
    this.maxMs,
  });

  final String host;
  final String method;
  final int? minStatus;
  final int? maxStatus;
  final int? minMs;
  final int? maxMs;

  bool get active =>
      host.isNotEmpty ||
      method.isNotEmpty ||
      minStatus != null ||
      maxStatus != null ||
      minMs != null ||
      maxMs != null;

  bool matches(VigilHttpCall call) =>
      (host.isEmpty || call.request.uri.host.toLowerCase() == host) &&
      (method.isEmpty || call.request.method.toUpperCase() == method) &&
      _inRange(call.response?.statusCode, minStatus, maxStatus) &&
      _inRange(
        call.duration == null ? null : call.duration!.inMicroseconds / 1000,
        minMs,
        maxMs,
      );

  bool _inRange(num? value, int? min, int? max) =>
      (min == null && max == null) ||
      (value != null &&
          (min == null || value >= min) &&
          (max == null || value <= max));
}

class _FilterDialog extends StatefulWidget {
  const _FilterDialog(this.filters, this.calls);

  final _AdvancedFilters filters;
  final List<VigilHttpCall> calls;

  @override
  State<_FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends State<_FilterDialog> {
  final _form = GlobalKey<FormState>();
  late String _host = widget.filters.host;
  late String _method = widget.filters.method;
  late final _bounds = [
    for (final value in [
      widget.filters.minStatus,
      widget.filters.maxStatus,
      widget.filters.minMs,
      widget.filters.maxMs,
    ])
      TextEditingController(text: value?.toString() ?? ''),
  ];

  @override
  void dispose() {
    for (final controller in _bounds) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hosts = {
      if (_host.isNotEmpty) _host,
      ...widget.calls
          .map((call) => call.request.uri.host.toLowerCase())
          .where((host) => host.isNotEmpty),
    }.toList()
      ..sort();
    final methods = {
      'GET',
      'HEAD',
      'POST',
      'PUT',
      'DELETE',
      'CONNECT',
      'OPTIONS',
      'TRACE',
      'PATCH',
      if (_method.isNotEmpty) _method,
      ...widget.calls.map((call) => call.request.method.toUpperCase()),
    }.toList()
      ..sort();
    return AlertDialog(
      title: const Text('Advanced filters'),
      scrollable: true,
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dropdown(
                'Host', _host, hosts, (value) => setState(() => _host = value)),
            _dropdown('Method', _method, methods,
                (value) => setState(() => _method = value)),
            for (final (index, label) in [
              'Minimum status',
              'Maximum status',
              'Minimum duration (ms)',
              'Maximum duration (ms)',
            ].indexed)
              TextFormField(
                controller: _bounds[index],
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: label),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return null;
                  final number = int.tryParse(value.trim());
                  if (number == null ||
                      number < 0 ||
                      (index < 2 && (number < 100 || number > 599))) {
                    return index < 2
                        ? 'Enter a status from 100 to 599'
                        : 'Enter a positive duration or zero';
                  }
                  final lower = index.isOdd
                      ? int.tryParse(_bounds[index - 1].text.trim())
                      : null;
                  return lower != null && number < lower
                      ? 'Maximum must be at least the minimum'
                      : null;
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, const _AdvancedFilters()),
            child: const Text('Reset')),
        FilledButton(onPressed: _apply, child: const Text('Apply')),
      ],
    );
  }

  Widget _dropdown(String label, String selected, List<String> values,
          ValueChanged<String> onChanged) =>
      DropdownButtonFormField<String>(
        // ignore: deprecated_member_use
        value: selected,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          const DropdownMenuItem(value: '', child: Text('Any')),
          for (final value in values)
            DropdownMenuItem(
                value: value,
                child: Text(value, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (value) => onChanged(value ?? ''),
      );

  void _apply() {
    if (!_form.currentState!.validate()) return;
    final values =
        _bounds.map((field) => int.tryParse(field.text.trim())).toList();
    Navigator.pop(
        context,
        _AdvancedFilters(
          host: _host,
          method: _method,
          minStatus: values[0],
          maxStatus: values[1],
          minMs: values[2],
          maxMs: values[3],
        ));
  }
}

Future<void> _chooseComparison(
  BuildContext context,
  VigilHttpCall call,
  List<VigilHttpCall> calls,
) async {
  final other = await showDialog<VigilHttpCall>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Compare with'),
      children: [
        for (final candidate
            in calls.reversed.where((item) => item.id != call.id))
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, candidate),
            child: Text(
                '${candidate.request.method} ${candidate.request.uri.path} · '
                '${candidate.response?.statusCode ?? candidate.state.name} · ${_formatTime(candidate.startedAt)}'),
          ),
      ],
    ),
  );
  if (!context.mounted || other == null) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => _ComparisonPage(before: other, after: call),
  ));
}

class _ComparisonPage extends StatelessWidget {
  const _ComparisonPage({required this.before, required this.after});

  final VigilHttpCall before;
  final VigilHttpCall after;

  Map<String, Object?> _fields(VigilHttpCall call) {
    final response = call.response;
    return {
      'Method': call.request.method,
      'URL': call.request.uri.toString(),
      'Status': response?.statusCode,
      'Duration (ms)': call.duration?.inMicroseconds == null
          ? null
          : call.duration!.inMicroseconds / 1000,
      'Failure': call.error?.message,
      'Request headers': {
        for (final header in call.request.headers.entries)
          header.key.toLowerCase(): header.value
      },
      'Request body': _body(call.request.body),
      'Response headers': {
        for (final header
            in (response?.headers ?? const <String, String>{}).entries)
          header.key.toLowerCase(): header.value
      },
      'Response body': _body(response?.body),
    };
  }

  Object? _body(VigilBodySummary? body) {
    if (body == null) return null;
    if (body.kind == VigilBodyKind.json && !body.truncated) {
      try {
        return jsonDecode(body.text ?? '');
      } on FormatException {
        return body.text;
      }
    }
    return body.text ??
        (body.kind == VigilBodyKind.empty ? null : body.kind.name);
  }

  @override
  Widget build(BuildContext context) {
    final changes = <(String, Object?, Object?)>[];
    _compare('', _fields(before), _fields(after), changes);
    return Scaffold(
      appBar: AppBar(title: const Text('Request comparison')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
              'Before · ${_formatTime(before.startedAt)}    After · ${_formatTime(after.startedAt)}'),
          if (changes.isEmpty) const ListTile(title: Text('No differences')),
          for (final (path, left, right) in changes)
            _Section(
                title: path,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Before'),
                    _CodeBlock(_display(left)),
                    const Text('After'),
                    _CodeBlock(_display(right)),
                  ],
                )),
        ],
      ),
    );
  }

  static final _missing = Object();

  String _display(Object? value) => identical(value, _missing)
      ? 'Absent'
      : const JsonEncoder.withIndent('  ').convert(value);

  void _compare(String path, Object? left, Object? right,
      List<(String, Object?, Object?)> changes) {
    if (left is Map && right is Map) {
      for (final key in {...left.keys, ...right.keys}) {
        final childPath =
            path.isEmpty ? key.toString() : '$path[${jsonEncode(key)}]';
        _compare(childPath, left.containsKey(key) ? left[key] : _missing,
            right.containsKey(key) ? right[key] : _missing, changes);
      }
    } else if (left is List && right is List) {
      final length = left.length > right.length ? left.length : right.length;
      for (var i = 0; i < length; i++) {
        _compare('$path[$i]', i < left.length ? left[i] : _missing,
            i < right.length ? right[i] : _missing, changes);
      }
    } else if (left != right) {
      changes.add((path, left, right));
    }
  }
}

class _ReplayDialog extends StatefulWidget {
  const _ReplayDialog(this.call, this.replay);

  final VigilHttpCall call;
  final VigilReplay replay;

  @override
  State<_ReplayDialog> createState() => _ReplayDialogState();
}

class _ReplayDialogState extends State<_ReplayDialog> {
  late final _method = TextEditingController(text: widget.call.request.method);
  late final _url =
      TextEditingController(text: widget.call.request.uri.toString());
  final _headers = TextEditingController(text: '{}');
  late final _body = TextEditingController(
    text: widget.call.request.body.kind == VigilBodyKind.json &&
            !widget.call.request.body.truncated &&
            !(widget.call.request.body.contentType?.startsWith('multipart/') ??
                false)
        ? widget.call.request.body.text
        : null,
  );
  bool _sending = false;
  String? _result;

  @override
  void dispose() {
    for (final controller in [_method, _url, _headers, _body]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Edit and replay'),
        scrollable: true,
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (controller, label, lines) in [
                (_method, 'Method', 1),
                (_url, 'URL', 1),
                (_headers, 'Additional headers (JSON object)', 3),
                (_body, 'JSON body (optional)', 5),
              ])
                TextField(
                  controller: controller,
                  enabled: !_sending,
                  maxLines: lines,
                  decoration: InputDecoration(labelText: label),
                ),
              if (widget.call.request.body.kind != VigilBodyKind.empty &&
                  _body.text.isEmpty)
                const Text(
                    'Enter the complete JSON body if the request needs one.'),
              if (_result != null) Text(_result!),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: _sending ? null : () => Navigator.pop(context),
              child: const Text('Close')),
          FilledButton(
              onPressed: _sending ? null : _send,
              child: Text(_sending ? 'Sending…' : 'Send request')),
        ],
      );

  Future<void> _send() async {
    final method = _method.text.trim().toUpperCase();
    final uri = Uri.tryParse(_url.text.trim());
    final original = widget.call.request.uri;
    if (uri == null ||
        !{'http', 'https'}.contains(original.scheme) ||
        !vigilMatchesOrigin(uri, {original.origin}) ||
        !RegExp(r'^[A-Z]+$').hasMatch(method)) {
      setState(
          () => _result = 'Enter a method and a URL on the original origin.');
      return;
    }
    final Map<String, String> headers;
    final body = _body.text.trim();
    try {
      headers = Map<String, String>.from(jsonDecode(_headers.text) as Map);
      if (body.isNotEmpty) jsonDecode(body);
    } catch (_) {
      setState(() =>
          _result = 'Enter valid JSON and use string values for headers.');
      return;
    }
    setState(() {
      _sending = true;
      _result = null;
    });
    try {
      if (!const {'GET', 'HEAD', 'OPTIONS'}.contains(method)) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Send $method request?'),
            content: const Text(
                'This request can change data on the development server.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Send')),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
      }
      final status = await widget.replay(VigilReplayRequest(
        originalUri: widget.call.request.uri,
        uri: uri,
        method: method,
        headers: headers,
        jsonBody: body.isEmpty ? null : body,
      ));
      if (mounted) {
        setState(() => _result =
            status == null ? 'Request sent' : 'Response status $status');
      }
    } on FormatException catch (error) {
      if (mounted) setState(() => _result = error.message);
    } catch (_) {
      if (mounted) {
        setState(() =>
            _result = 'Replay failed. Check the captured request for details.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

class _MocksPage extends StatefulWidget {
  const _MocksPage(this.mocks);

  final VigilMockController mocks;

  @override
  State<_MocksPage> createState() => _MocksPageState();
}

class _MocksPageState extends State<_MocksPage> {
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Mock responses')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _add,
          label: const Text('Add rule'),
          icon: const Icon(Icons.add),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
          children: [
            Text('Applies to ${widget.mocks.allowedOrigins.join(', ')}'),
            if (widget.mocks.rules.isEmpty)
              const ListTile(title: Text('No mock rules')),
            for (final rule in widget.mocks.rules)
              ListTile(
                title: Text('${rule.method} ${rule.path}'),
                subtitle: Text('${_effectLabel(rule.effect)}'
                    '${rule.effect == VigilMockEffect.response ? ' · ${rule.statusCode}' : ''}'
                    ' · ${rule.delay.inMilliseconds} ms'),
                trailing: IconButton(
                  tooltip: 'Remove rule',
                  onPressed: () => setState(() => widget.mocks.remove(rule)),
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
          ],
        ),
      );

  Future<void> _add() async {
    final rule = await showDialog<VigilMockRule>(
      context: context,
      builder: (_) => const _MockRuleDialog(),
    );
    if (mounted && rule != null) setState(() => widget.mocks.put(rule));
  }
}

String _effectLabel(VigilMockEffect effect) => switch (effect) {
      VigilMockEffect.response => 'Mock response',
      VigilMockEffect.timeout => 'Timeout',
      VigilMockEffect.connectionError => 'Connection error',
      VigilMockEffect.delay => 'Delay and forward',
    };

class _MockRuleDialog extends StatefulWidget {
  const _MockRuleDialog();

  @override
  State<_MockRuleDialog> createState() => _MockRuleDialogState();
}

class _MockRuleDialogState extends State<_MockRuleDialog> {
  final _method = TextEditingController(text: 'GET');
  final _path = TextEditingController();
  final _delay = TextEditingController(text: '0');
  final _status = TextEditingController(text: '500');
  final _body = TextEditingController(text: '{"error":"Simulated failure"}');
  VigilMockEffect _effect = VigilMockEffect.response;
  String? _error;

  @override
  void dispose() {
    for (final controller in [_method, _path, _delay, _status, _body]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add mock rule'),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<VigilMockEffect>(
              // ignore: deprecated_member_use
              value: _effect,
              decoration: const InputDecoration(labelText: 'Effect'),
              items: [
                for (final effect in VigilMockEffect.values)
                  DropdownMenuItem(
                      value: effect, child: Text(_effectLabel(effect))),
              ],
              onChanged: (value) => setState(() => _effect = value ?? _effect),
            ),
            for (final (controller, label, lines) in [
              (_method, 'Method', 1),
              (_path, 'Exact path', 1),
              (_delay, 'Delay (ms)', 1),
              if (_effect == VigilMockEffect.response) ...[
                (_status, 'Status code', 1),
                (_body, 'JSON body', 4),
              ],
            ])
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: TextField(
                  controller: controller,
                  maxLines: lines,
                  decoration: InputDecoration(labelText: label),
                ),
              ),
            if (_error != null) Text(_error!),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(onPressed: _save, child: const Text('Save rule')),
        ],
      );

  void _save() {
    try {
      final delay = int.tryParse(_delay.text.trim());
      if (delay == null) {
        throw const FormatException('Enter a delay in milliseconds.');
      }
      if (_path.text.contains('?') || _path.text.contains('#')) {
        throw const FormatException(
            'Enter the path without a query or fragment.');
      }
      Navigator.pop(
          context,
          VigilMockRule(
            method: _method.text.trim().toUpperCase(),
            path: _path.text.trim(),
            effect: _effect,
            statusCode: int.tryParse(_status.text.trim()) ?? 0,
            jsonBody: _body.text,
            delay: Duration(milliseconds: delay),
          ));
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }
}
