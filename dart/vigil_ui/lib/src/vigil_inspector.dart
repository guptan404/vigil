import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vigil_core/vigil_core.dart';

class VigilInspector extends StatefulWidget {
  const VigilInspector({super.key, this.vigil, this.onClose});

  final Vigil? vigil;
  final VoidCallback? onClose;

  @override
  State<VigilInspector> createState() => _VigilInspectorState();
}

class _VigilInspectorState extends State<VigilInspector> {
  String? _selectedCallId;

  Vigil get _vigil => widget.vigil ?? Vigil.instance;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<VigilEvent>(
      stream: _vigil.events,
      builder: (context, _) {
        final calls = _vigil.calls.reversed.toList(growable: false);
        final selectedCall = _selectedCall(calls);

        return Scaffold(
          backgroundColor: _surfaceBase(context),
          appBar: AppBar(
            titleSpacing: 16,
            title: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Vigil'),
                Text(
                  'Network inspector',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Clear',
                onPressed: calls.isEmpty ? null : _vigil.clear,
                icon: const Icon(Icons.delete_outline),
              ),
              if (widget.onClose != null)
                IconButton(
                  tooltip: 'Close',
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          body: calls.isEmpty
              ? const _EmptyState()
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 900;
                    if (!isWide) {
                      return _CallListView(
                        calls: calls,
                        selectedCallId: selectedCall?.id,
                        onSelected: (call) {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => _CallDetailPage(
                                call: call,
                                vigil: _vigil,
                              ),
                            ),
                          );
                        },
                      );
                    }

                    return Row(
                      children: [
                        SizedBox(
                          width: 380,
                          child: _CallListView(
                            calls: calls,
                            selectedCallId: selectedCall?.id,
                            onSelected: (call) {
                              setState(() => _selectedCallId = call.id);
                            },
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(
                          child: selectedCall == null
                              ? const _EmptyState()
                              : _CallDetailPane(call: selectedCall, vigil: _vigil),
                        ),
                      ],
                    );
                  },
                ),
        );
      },
    );
  }

  VigilHttpCall? _selectedCall(List<VigilHttpCall> calls) {
    if (calls.isEmpty) return null;

    final selectedId = _selectedCallId;
    if (selectedId != null) {
      for (final call in calls) {
        if (call.id == selectedId) return call;
      }
    }

    return calls.first;
  }
}

class _CallListView extends StatelessWidget {
  const _CallListView({
    required this.calls,
    required this.selectedCallId,
    required this.onSelected,
  });

  final List<VigilHttpCall> calls;
  final String? selectedCallId;
  final ValueChanged<VigilHttpCall> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        _SummaryStrip(calls: calls),
        const SizedBox(height: 12),
        for (final call in calls) ...[
          _CallTile(
            call: call,
            selected: call.id == selectedCallId,
            onTap: () => onSelected(call),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.calls});

  final List<VigilHttpCall> calls;

  @override
  Widget build(BuildContext context) {
    final failed = calls.where((call) => call.state == VigilCallState.failed).length;
    final slow = calls.where((call) {
      final duration = call.duration;
      return duration != null && duration.inMilliseconds >= 1000;
    }).length;
    final latest = calls.isEmpty ? null : calls.first;

    return _Panel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _MetricTile(label: 'Calls', value: '${calls.length}')),
              Expanded(child: _MetricTile(label: 'Failed', value: '$failed')),
              Expanded(child: _MetricTile(label: 'Slow', value: '$slow')),
            ],
          ),
          if (latest != null) ...[
            const SizedBox(height: 10),
            Text(
              'Latest ${latest.request.method} ${_shortPath(latest.request.uri)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 2),
        Text(value, style: Theme.of(context).textTheme.titleLarge),
      ],
    );
  }
}

class _CallTile extends StatelessWidget {
  const _CallTile({
    required this.call,
    required this.selected,
    required this.onTap,
  });

  final VigilHttpCall call;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final response = call.response;
    final status = response?.statusCode.toString() ?? call.state.name;
    final duration = call.duration;
    final color = _statusColor(response?.statusCode, call.state);

    return _Panel(
      selected: selected,
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _Badge(text: call.request.method, color: _methodColor(call.request.method)),
                  const SizedBox(width: 8),
                  _Badge(text: status, color: color),
                  const Spacer(),
                  Text(
                    duration == null ? 'pending' : '${duration.inMilliseconds} ms',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _shortPath(call.request.uri),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                call.request.uri.host,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallDetailPage extends StatelessWidget {
  const _CallDetailPage({required this.call, required this.vigil});

  final VigilHttpCall call;
  final Vigil vigil;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surfaceBase(context),
      appBar: AppBar(title: Text('${call.request.method} ${_shortPath(call.request.uri)}')),
      body: _CallDetailPane(call: call, vigil: vigil),
    );
  }
}

class _CallDetailPane extends StatelessWidget {
  const _CallDetailPane({required this.call, required this.vigil});

  final VigilHttpCall call;
  final Vigil vigil;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DetailHeader(call: call),
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Payload'),
              Tab(text: 'Headers'),
              Tab(text: 'Timing'),
              Tab(text: 'Debug'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _OverviewTab(call: call, vigil: vigil),
                _PayloadTab(call: call),
                _HeadersTab(call: call),
                _TimingTab(call: call),
                _ServerDebugTab(call: call),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({required this.call});

  final VigilHttpCall call;

  @override
  Widget build(BuildContext context) {
    final response = call.response;
    final duration = call.duration;
    final status = response?.statusCode.toString() ?? call.state.name;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: _Panel(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Badge(text: call.request.method, color: _methodColor(call.request.method)),
                const SizedBox(width: 8),
                _Badge(text: status, color: _statusColor(response?.statusCode, call.state)),
                const Spacer(),
                if (duration != null)
                  _Badge(text: '${duration.inMilliseconds} ms', color: Colors.indigo),
              ],
            ),
            const SizedBox(height: 12),
            SelectableText(
              call.request.uri.toString(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(label: 'Host', value: call.request.uri.host),
                _InfoChip(label: 'Started', value: _formatTime(call.startedAt)),
                _InfoChip(label: 'Trace', value: call.request.traceContext.traceId),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.call, required this.vigil});

  final VigilHttpCall call;
  final Vigil vigil;

  @override
  Widget build(BuildContext context) {
    final curl = vigil.toCurl(call);
    final response = call.response;
    final error = call.error;

    return _TabList(
      children: [
        _Section(
          title: 'Request',
          child: Column(
            children: [
              _KeyValueRow('URL', call.request.uri.toString()),
              _KeyValueRow('Method', call.request.method),
              _KeyValueRow('State', call.state.name),
              _KeyValueRow('Trace ID', call.request.traceContext.traceId),
            ],
          ),
        ),
        _Section(
          title: 'Response',
          child: Column(
            children: [
              _KeyValueRow('Status', response == null ? '-' : '${response.statusCode} ${response.statusMessage ?? ''}'.trim()),
              _KeyValueRow('Duration', call.duration == null ? '-' : '${call.duration!.inMilliseconds} ms'),
              _KeyValueRow('Server timings', '${response?.serverTimings.length ?? 0}'),
            ],
          ),
        ),
        if (error != null)
          _Section(
            title: 'Error',
            child: Column(
              children: [
                _KeyValueRow('Type', error.type ?? '-'),
                _KeyValueRow('Message', error.message),
              ],
            ),
          ),
        _Section(
          title: 'cURL',
          trailing: TextButton.icon(
            onPressed: () => Clipboard.setData(ClipboardData(text: curl)),
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy'),
          ),
          child: _CodeBlock(curl),
        ),
      ],
    );
  }
}

class _PayloadTab extends StatelessWidget {
  const _PayloadTab({required this.call});

  final VigilHttpCall call;

  @override
  Widget build(BuildContext context) {
    final response = call.response;

    return _TabList(
      children: [
        _Section(title: 'Request Body', child: _BodyView(call.request.body)),
        _Section(
          title: 'Response Body',
          child: response == null
              ? const _MutedText('No response captured')
              : _BodyView(response.body),
        ),
      ],
    );
  }
}

class _HeadersTab extends StatelessWidget {
  const _HeadersTab({required this.call});

  final VigilHttpCall call;

  @override
  Widget build(BuildContext context) {
    return _TabList(
      children: [
        _Section(title: 'Request Headers', child: _HeadersTable(call.request.headers)),
        _Section(
          title: 'Response Headers',
          child: call.response == null
              ? const _MutedText('No response captured')
              : _HeadersTable(call.response!.headers),
        ),
      ],
    );
  }
}

class _TimingTab extends StatelessWidget {
  const _TimingTab({required this.call});

  final VigilHttpCall call;

  @override
  Widget build(BuildContext context) {
    final timings = call.response?.serverTimings ?? const <VigilServerTiming>[];
    final maxDuration = timings.fold<double>(
      1,
      (max, timing) {
        final duration = timing.duration ?? 0;
        return duration > max ? duration : max;
      },
    );

    return _TabList(
      children: [
        _Section(
          title: 'Client Timing',
          child: Column(
            children: [
              _KeyValueRow('Started', _formatTime(call.startedAt)),
              _KeyValueRow('Completed', call.completedAt == null ? '-' : _formatTime(call.completedAt!)),
              _KeyValueRow('Duration', call.duration == null ? '-' : '${call.duration!.inMilliseconds} ms'),
            ],
          ),
        ),
        _Section(
          title: 'Server-Timing',
          child: timings.isEmpty
              ? const _MutedText('No server timing metrics captured')
              : Column(
                  children: [
                    for (final timing in timings)
                      _TimingRow(timing: timing, maxDuration: maxDuration),
                  ],
                ),
        ),
      ],
    );
  }
}

class _TimingRow extends StatelessWidget {
  const _TimingRow({required this.timing, required this.maxDuration});

  final VigilServerTiming timing;
  final double maxDuration;

  @override
  Widget build(BuildContext context) {
    final duration = timing.duration;
    final fraction = duration == null ? 0.0 : (duration / maxDuration).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(timing.name, style: Theme.of(context).textTheme.titleSmall)),
              Text(duration == null ? '-' : '${duration.toStringAsFixed(1)} ms'),
            ],
          ),
          if (timing.description != null && timing.description!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(timing.description!, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
            borderRadius: BorderRadius.circular(6),
          ),
        ],
      ),
    );
  }
}

class _ServerDebugTab extends StatelessWidget {
  const _ServerDebugTab({required this.call});

  final VigilHttpCall call;

  @override
  Widget build(BuildContext context) {
    final debug = call.response?.serverDebug;

    if (debug == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: _MutedText('No gated server debug payload captured'),
        ),
      );
    }

    return _TabList(
      children: [
        _Section(
          title: 'Server Debug',
          child: Column(
            children: [
              _KeyValueRow('Error', debug.error ?? '-'),
              _KeyValueRow('Truncated', debug.truncated ? 'Yes' : 'No'),
            ],
          ),
        ),
        _Section(
          title: 'Stack',
          child: _CodeBlock(debug.stack ?? '-'),
        ),
        _Section(
          title: 'Context',
          child: debug.context.isEmpty
              ? const _MutedText('No context')
              : Column(
                  children: [
                    for (final entry in debug.context.entries)
                      _KeyValueRow(entry.key, '${entry.value}'),
                  ],
                ),
        ),
      ],
    );
  }
}

class _TabList extends StatelessWidget {
  const _TabList({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: children.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => children[index],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(title, style: Theme.of(context).textTheme.titleMedium),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.selected = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? scheme.primary.withValues(alpha: 0.08) : scheme.surface,
        border: Border.all(
          color: selected ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.7),
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _BodyView extends StatelessWidget {
  const _BodyView(this.body);

  final VigilBodySummary body;

  @override
  Widget build(BuildContext context) {
    if (body.kind == VigilBodyKind.empty) return const _MutedText('Empty body');
    if (body.kind == VigilBodyKind.unavailable) {
      return const _MutedText('Body unavailable');
    }
    if (body.kind == VigilBodyKind.binary) {
      return _MutedText('Binary body (${body.byteLength} bytes)');
    }
    if (body.kind == VigilBodyKind.oversized) {
      return _MutedText('Body oversized (${body.byteLength} bytes)');
    }

    final text = _prettyBody(body);
    final suffix = body.truncated ? '\n\n[truncated at ${body.text?.length ?? 0} chars]' : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _InfoChip(label: 'Kind', value: body.kind.name),
            _InfoChip(label: 'Bytes', value: '${body.byteLength}'),
            if (body.contentType != null) _InfoChip(label: 'Type', value: body.contentType!),
          ],
        ),
        const SizedBox(height: 12),
        _CodeBlock('$text$suffix'),
      ],
    );
  }
}

class _HeadersTable extends StatelessWidget {
  const _HeadersTable(this.headers);

  final Map<String, String> headers;

  @override
  Widget build(BuildContext context) {
    if (headers.isEmpty) return const _MutedText('No headers');
    return Column(
      children: [
        for (final entry in headers.entries) _KeyValueRow(entry.key, entry.value),
      ],
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 3),
          SelectableText(value),
        ],
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.65)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SelectableText(
            text,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          text,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _MutedText extends StatelessWidget {
  const _MutedText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.network_check,
              size: 44,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text('No network calls captured', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            const _MutedText('Make a Dio request and it will appear here.'),
          ],
        ),
      ),
    );
  }
}

Color _surfaceBase(BuildContext context) {
  return Theme.of(context).colorScheme.surfaceContainerLowest;
}

Color _methodColor(String method) {
  return switch (method.toUpperCase()) {
    'GET' => Colors.blue,
    'POST' => Colors.green,
    'PUT' || 'PATCH' => Colors.orange,
    'DELETE' => Colors.red,
    _ => Colors.grey,
  };
}

Color _statusColor(int? status, VigilCallState state) {
  if (state == VigilCallState.failed) return Colors.red;
  if (status == null) return Colors.grey;
  if (status >= 500) return Colors.red;
  if (status >= 400) return Colors.deepOrange;
  if (status >= 300) return Colors.purple;
  if (status >= 200) return Colors.green;
  return Colors.grey;
}

String _shortPath(Uri uri) {
  final path = uri.path.isEmpty ? '/' : uri.path;
  if (uri.query.isEmpty) return path;
  return '$path?${uri.query}';
}

String _formatTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  final second = local.second.toString().padLeft(2, '0');
  return '$hour:$minute:$second';
}

String _prettyBody(VigilBodySummary body) {
  final text = body.text ?? '';
  if (body.kind != VigilBodyKind.json || text.isEmpty) return text;

  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(text));
  } catch (_) {
    return text;
  }
}
