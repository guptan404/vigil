import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vigil_core/vigil_core.dart';

/// Searchable Flutter interface for requests captured by Vigil.
class VigilInspector extends StatefulWidget {
  /// Creates an inspector for [vigil] or [Vigil.instance].
  const VigilInspector({super.key, this.vigil, this.onClose});

  /// Recorder whose calls are displayed.
  final Vigil? vigil;

  /// Optional callback exposed as a close action in the app bar.
  final VoidCallback? onClose;

  @override
  State<VigilInspector> createState() => _VigilInspectorState();
}

class _VigilInspectorState extends State<VigilInspector> {
  String? _selectedCallId;
  final TextEditingController _searchController = TextEditingController();
  _CallFilter _filter = _CallFilter.all;
  String _query = '';

  Vigil get _vigil => widget.vigil ?? Vigil.instance;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<VigilEvent>(
      stream: _vigil.events,
      builder: (context, _) {
        final calls = _vigil.calls.reversed.toList(growable: false);
        final visibleCalls = _filteredCalls(calls);
        final selectedCall = _selectedCall(visibleCalls);

        return Theme(
          data: _inspectorTheme(context),
          child: Builder(
            builder: (context) => Scaffold(
              backgroundColor: _surfaceBase(context),
              appBar: _InspectorAppBar(
                hasCalls: calls.isNotEmpty,
                onClear: _vigil.clear,
                onClose: widget.onClose,
              ),
              body: calls.isEmpty
                  ? const _EmptyState()
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 840;
                        final list = _CallListView(
                          calls: calls,
                          visibleCalls: visibleCalls,
                          selectedCallId: isWide ? selectedCall?.id : null,
                          searchController: _searchController,
                          query: _query,
                          filter: _filter,
                          onQueryChanged: (value) {
                            setState(() => _query = value.trim().toLowerCase());
                          },
                          onFilterChanged: (value) {
                            setState(() => _filter = value);
                          },
                          onSelected: (call) {
                            if (isWide) {
                              setState(() => _selectedCallId = call.id);
                              return;
                            }
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

                        if (!isWide) return list;

                        return Row(
                          children: [
                            SizedBox(width: 420, child: list),
                            const VerticalDivider(width: 1),
                            Expanded(
                              child: selectedCall == null
                                  ? const _NoResultsState()
                                  : _CallDetailPane(
                                      call: selectedCall,
                                      vigil: _vigil,
                                    ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
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

  List<VigilHttpCall> _filteredCalls(List<VigilHttpCall> calls) {
    return calls.where((call) {
      if (!_filter.matches(call)) return false;
      if (_query.isEmpty) return true;

      final responseStatus = call.response?.statusCode.toString() ?? '';
      final searchable = <String>[
        call.request.method,
        call.request.uri.toString(),
        call.request.uri.host,
        call.state.name,
        responseStatus,
        call.error?.message ?? '',
      ].join(' ').toLowerCase();
      return searchable.contains(_query);
    }).toList(growable: false);
  }
}

enum _CallFilter { all, failed, slow, post, get }

extension on _CallFilter {
  String get label => switch (this) {
        _CallFilter.all => 'All',
        _CallFilter.failed => 'Failed',
        _CallFilter.slow => 'Slow',
        _CallFilter.post => 'POST',
        _CallFilter.get => 'GET',
      };

  bool matches(VigilHttpCall call) => switch (this) {
        _CallFilter.all => true,
        _CallFilter.failed => call.state == VigilCallState.failed ||
            (call.response?.statusCode ?? 0) >= 400,
        _CallFilter.slow => _isSlow(call),
        _CallFilter.post => call.request.method.toUpperCase() == 'POST',
        _CallFilter.get => call.request.method.toUpperCase() == 'GET',
      };
}

class _InspectorAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _InspectorAppBar({
    required this.hasCalls,
    required this.onClear,
    required this.onClose,
  });

  final bool hasCalls;
  final VoidCallback onClear;
  final VoidCallback? onClose;

  @override
  Size get preferredSize => const Size.fromHeight(72);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppBar(
      toolbarHeight: preferredSize.height,
      titleSpacing: 20,
      title: Row(
        children: [
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vigil',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                ),
                Text(
                  'Network inspector',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'LIVE',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Clear requests',
          onPressed: hasCalls ? onClear : null,
          icon: const Icon(Icons.delete_outline_rounded),
        ),
        if (onClose != null)
          IconButton(
            tooltip: 'Close inspector',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
        const SizedBox(width: 8),
      ],
    );
  }
}

class _CallListView extends StatelessWidget {
  const _CallListView({
    required this.calls,
    required this.visibleCalls,
    required this.selectedCallId,
    required this.searchController,
    required this.query,
    required this.filter,
    required this.onQueryChanged,
    required this.onFilterChanged,
    required this.onSelected,
  });

  final List<VigilHttpCall> calls;
  final List<VigilHttpCall> visibleCalls;
  final String? selectedCallId;
  final TextEditingController searchController;
  final String query;
  final _CallFilter filter;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<_CallFilter> onFilterChanged;
  final ValueChanged<VigilHttpCall> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SummaryStrip(calls: calls),
              const SizedBox(height: 14),
              TextField(
                controller: searchController,
                onChanged: onQueryChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search requests',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            searchController.clear();
                            onQueryChanged('');
                          },
                          icon: const Icon(Icons.close_rounded, size: 20),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _CallFilter.values.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final value = _CallFilter.values[index];
                    return ChoiceChip(
                      label: Text(value.label),
                      selected: value == filter,
                      onSelected: (_) => onFilterChanged(value),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: visibleCalls.isEmpty
              ? const _NoResultsState()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 20),
                  itemCount: visibleCalls.length,
                  separatorBuilder: (_, __) => const Divider(
                    height: 1,
                    indent: 76,
                    endIndent: 8,
                  ),
                  itemBuilder: (context, index) {
                    final call = visibleCalls[index];
                    return _CallTile(
                      call: call,
                      selected: call.id == selectedCallId,
                      onTap: () => onSelected(call),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.calls});

  final List<VigilHttpCall> calls;

  @override
  Widget build(BuildContext context) {
    final failed = calls.where((call) {
      return call.state == VigilCallState.failed ||
          (call.response?.statusCode ?? 0) >= 400;
    }).length;
    final slow = calls.where(_isSlow).length;
    final scheme = Theme.of(context).colorScheme;

    return Text.rich(
      TextSpan(
        style: Theme.of(context).textTheme.labelLarge,
        children: [
          TextSpan(
            text: '${calls.length}',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          TextSpan(text: calls.length == 1 ? ' request' : ' requests'),
          TextSpan(text: '  •  ', style: TextStyle(color: scheme.outline)),
          TextSpan(
            text: '$failed',
            style: TextStyle(
              color: failed == 0 ? null : scheme.error,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const TextSpan(text: ' failed'),
          TextSpan(text: '  •  ', style: TextStyle(color: scheme.outline)),
          TextSpan(
            text: '$slow',
            style: TextStyle(
              color: slow == 0 ? null : _warningColor(context),
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const TextSpan(text: ' slow'),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _NoResultsState extends StatelessWidget {
  const _NoResultsState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_alt_off_outlined,
              size: 32,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 10),
            Text(
              'No matching requests',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            const _MutedText('Try a different search or filter.'),
          ],
        ),
      ),
    );
  }
}

class _RequestMeta extends StatelessWidget {
  const _RequestMeta({required this.call, required this.statusColor});

  final VigilHttpCall call;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    final status = call.response?.statusCode.toString() ?? call.state.name;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: muted);

    return LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          Flexible(
            child: Text(
              call.request.uri.host.isEmpty
                  ? 'Local request'
                  : call.request.uri.host,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text('•', style: style),
          ),
          Text(
            status,
            style: style?.copyWith(
              color: statusColor,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (constraints.maxWidth >= 210) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text('•', style: style),
            ),
            Text(_formatTime(call.startedAt), style: style),
          ],
        ],
      ),
    );
  }
}

class _DurationLabel extends StatelessWidget {
  const _DurationLabel({required this.call});

  final VigilHttpCall call;

  @override
  Widget build(BuildContext context) {
    final duration = call.duration;
    final failed = call.state == VigilCallState.failed ||
        (call.response?.statusCode ?? 0) >= 400;
    final color = failed
        ? Theme.of(context).colorScheme.error
        : _isSlow(call)
            ? _warningColor(context)
            : Theme.of(context).colorScheme.onSurface;

    return Text(
      duration == null ? 'pending' : _formatDuration(duration),
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

class _MethodBadge extends StatelessWidget {
  const _MethodBadge(this.method);

  final String method;

  @override
  Widget build(BuildContext context) {
    final color = _methodColor(method);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 50),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Text(
            method.toUpperCase(),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
      ),
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
    final color = _statusColor(response?.statusCode, call.state);
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      label: '${call.request.method} ${call.request.uri}, '
          '${response?.statusCode ?? call.state.name}, '
          '${call.duration == null ? 'pending' : _formatDuration(call.duration!)}',
      child: Material(
        color: selected
            ? scheme.primaryContainer.withValues(alpha: 0.36)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 78),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
              child: Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 11),
                  _MethodBadge(call.request.method),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _shortPath(call.request.uri),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.1,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        _RequestMeta(call: call, statusColor: color),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _DurationLabel(call: call),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: scheme.outline,
                  ),
                ],
              ),
            ),
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
    return Theme(
      data: _inspectorTheme(context),
      child: Builder(
        builder: (context) => Scaffold(
          backgroundColor: _surfaceBase(context),
          appBar: AppBar(
            title: const Text('Request details'),
            actions: [
              Builder(
                builder: (shareContext) => IconButton(
                  tooltip: 'Share lifecycle',
                  onPressed: () => _shareLifecycle(shareContext, call),
                  icon: const Icon(Icons.share_rounded),
                ),
              ),
              IconButton(
                tooltip: 'Copy cURL',
                onPressed: () => _copyWithFeedback(
                  context,
                  vigil.toCurl(call),
                  'cURL copied',
                ),
                icon: const Icon(Icons.terminal_rounded),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: _CallDetailPane(call: call, vigil: vigil),
        ),
      ),
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
          _DetailHeader(call: call, vigil: vigil),
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Request'),
              Tab(text: 'Response'),
              Tab(text: 'Timing'),
              Tab(text: 'Debug'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _OverviewTab(call: call, vigil: vigil),
                _RequestTab(call: call),
                _ResponseTab(call: call),
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
  const _DetailHeader({required this.call, required this.vigil});

  final VigilHttpCall call;
  final Vigil vigil;

  @override
  Widget build(BuildContext context) {
    final response = call.response;
    final duration = call.duration;
    final status = response?.statusCode.toString() ?? call.state.name;

    final statusColor = _statusColor(response?.statusCode, call.state);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        border: Border(
          bottom:
              BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _MethodBadge(call.request.method),
                const SizedBox(width: 8),
                _Badge(text: status, color: statusColor),
                const Spacer(),
                if (duration != null)
                  Text(
                    _formatDuration(duration),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: _isSlow(call)
                          ? _warningColor(context)
                          : Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              _pathOnly(call.request.uri),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 5),
            Text(
              call.request.uri.host.isEmpty
                  ? 'Local request'
                  : call.request.uri.host,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _copyWithFeedback(
                    context,
                    call.request.uri.toString(),
                    'URL copied',
                  ),
                  icon: const Icon(Icons.link_rounded, size: 18),
                  label: const Text('Copy URL'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _copyWithFeedback(
                    context,
                    vigil.toCurl(call),
                    'cURL copied',
                  ),
                  icon: const Icon(Icons.terminal_rounded, size: 18),
                  label: const Text('Copy cURL'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _copyWithFeedback(
                    context,
                    _lifecycleJson(call),
                    'Lifecycle copied',
                  ),
                  icon: const Icon(Icons.copy_all_rounded, size: 18),
                  label: const Text('Copy lifecycle'),
                ),
                Builder(
                  builder: (shareContext) => FilledButton.tonalIcon(
                    onPressed: () => _shareLifecycle(shareContext, call),
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: const Text('Share lifecycle'),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    child: Text(
                      'Started ${_formatTime(call.startedAt)}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
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
          title: 'Summary',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _KeyValueRow('Method', call.request.method),
              _KeyValueRow('State', call.state.name),
              _KeyValueRow('Started', _formatTime(call.startedAt)),
              _KeyValueRow('Trace ID', call.request.traceContext.traceId),
            ],
          ),
        ),
        _Section(
          title: 'Response',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _KeyValueRow(
                  'Status',
                  response == null
                      ? '-'
                      : '${response.statusCode} ${response.statusMessage ?? ''}'
                          .trim()),
              _KeyValueRow(
                  'Duration',
                  call.duration == null
                      ? '-'
                      : _formatDuration(call.duration!)),
              _KeyValueRow(
                  'Server timings', '${response?.serverTimings.length ?? 0}'),
            ],
          ),
        ),
        if (error != null)
          _Section(
            title: 'Error',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _KeyValueRow('Type', error.type ?? '-'),
                _KeyValueRow('Message', error.message),
              ],
            ),
          ),
        _Section(
          title: 'cURL',
          trailing: TextButton.icon(
            onPressed: () => _copyWithFeedback(context, curl, 'cURL copied'),
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy'),
          ),
          child: _CodeBlock(curl),
        ),
      ],
    );
  }
}

class _RequestTab extends StatelessWidget {
  const _RequestTab({required this.call});

  final VigilHttpCall call;

  @override
  Widget build(BuildContext context) {
    return _TabList(
      children: [
        _Section(
          title: 'Request',
          trailing: TextButton.icon(
            onPressed: () => _copyWithFeedback(
              context,
              call.request.uri.toString(),
              'URL copied',
            ),
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copy URL'),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _KeyValueRow('URL', call.request.uri.toString()),
              _KeyValueRow('Method', call.request.method),
              _KeyValueRow('Started', _formatTime(call.startedAt)),
              _KeyValueRow('Trace ID', call.request.traceContext.traceId),
            ],
          ),
        ),
        _Section(
          title: 'Query Parameters',
          child: _QueryParameters(call.request.uri.queryParametersAll),
        ),
        _Section(title: 'Headers', child: _HeadersTable(call.request.headers)),
        _Section(
          title: 'Body',
          trailing: _CopyBodyButton(
            body: call.request.body,
            feedback: 'Request body copied',
          ),
          child: _BodyView(call.request.body),
        ),
      ],
    );
  }
}

class _ResponseTab extends StatelessWidget {
  const _ResponseTab({required this.call});

  final VigilHttpCall call;

  @override
  Widget build(BuildContext context) {
    final response = call.response;
    if (response == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: _MutedText('No response captured'),
        ),
      );
    }

    return _TabList(
      children: [
        _Section(
          title: 'Response',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _KeyValueRow('Status', '${response.statusCode}'),
              _KeyValueRow('Message', response.statusMessage ?? '-'),
              _KeyValueRow(
                'Completed',
                call.completedAt == null ? '-' : _formatTime(call.completedAt!),
              ),
              _KeyValueRow(
                'Duration',
                call.duration == null ? '-' : _formatDuration(call.duration!),
              ),
            ],
          ),
        ),
        _Section(
          title: 'Headers',
          child: _HeadersTable(response.headers),
        ),
        _Section(
          title: 'Body',
          trailing: _CopyBodyButton(
            body: response.body,
            feedback: 'Response body copied',
          ),
          child: _BodyView(response.body),
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _KeyValueRow('Started', _formatTime(call.startedAt)),
              _KeyValueRow(
                  'Completed',
                  call.completedAt == null
                      ? '-'
                      : _formatTime(call.completedAt!)),
              _KeyValueRow(
                  'Duration',
                  call.duration == null
                      ? '-'
                      : '${call.duration!.inMilliseconds} ms'),
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
    final fraction =
        duration == null ? 0.0 : (duration / maxDuration).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(timing.name,
                      style: Theme.of(context).textTheme.titleSmall)),
              Text(
                  duration == null ? '-' : '${duration.toStringAsFixed(1)} ms'),
            ],
          ),
          if (timing.description != null && timing.description!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(timing.description!,
                style: Theme.of(context).textTheme.bodySmall),
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
    final response = call.response;
    final error = call.error;
    final hasFailure = error != null || (response?.statusCode ?? 0) >= 400;

    if (debug == null && !hasFailure) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: _MutedText('No failure or server debug payload captured'),
        ),
      );
    }

    return _TabList(
      children: [
        if (hasFailure)
          _Section(
            title: 'Failure',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _KeyValueRow(
                  'Status',
                  response == null
                      ? 'No server response'
                      : '${response.statusCode} ${response.statusMessage ?? ''}'
                          .trim(),
                ),
                if (error != null) ...[
                  _KeyValueRow('Type', error.type ?? '-'),
                  _KeyValueRow('Message', error.message),
                ],
                _KeyValueRow('Trace ID', call.request.traceContext.traceId),
              ],
            ),
          ),
        if (response != null && hasFailure)
          _Section(title: 'Response body', child: _BodyView(response.body)),
        if (debug != null) ...[
          _Section(
            title: 'Server Debug',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _KeyValueRow('Error', debug.error ?? '-'),
                _KeyValueRow('Truncated', debug.truncated ? 'Yes' : 'No'),
              ],
            ),
          ),
          _Section(title: 'Stack', child: _CodeBlock(debug.stack ?? '-')),
          _Section(
            title: 'Context',
            child: debug.context.isEmpty
                ? const _MutedText('No context')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final entry in debug.context.entries)
                        _KeyValueRow(entry.key, '${entry.value}'),
                    ],
                  ),
          ),
        ] else if (hasFailure)
          const _Section(
            title: 'Server Debug',
            child: _MutedText('No gated server debug payload received'),
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
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
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
                child:
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
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
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(padding: const EdgeInsets.all(14), child: child),
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
    final suffix = body.truncated
        ? '\n\n[truncated at ${body.text?.length ?? 0} chars]'
        : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _InfoChip(label: 'Kind', value: body.kind.name),
            _InfoChip(label: 'Bytes', value: '${body.byteLength}'),
            if (body.contentType != null)
              _InfoChip(label: 'Type', value: body.contentType!),
          ],
        ),
        const SizedBox(height: 12),
        _CodeBlock('$text$suffix'),
      ],
    );
  }
}

class _CopyBodyButton extends StatelessWidget {
  const _CopyBodyButton({required this.body, required this.feedback});

  final VigilBodySummary body;
  final String feedback;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: body.isDisplayable && body.text != null
          ? () => _copyWithFeedback(context, body.text ?? '', feedback)
          : null,
      icon: const Icon(Icons.copy_rounded, size: 18),
      label: const Text('Copy body'),
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in headers.entries)
          _KeyValueRow(entry.key, entry.value),
      ],
    );
  }
}

class _QueryParameters extends StatelessWidget {
  const _QueryParameters(this.parameters);

  final Map<String, List<String>> parameters;

  @override
  Widget build(BuildContext context) {
    if (parameters.isEmpty) {
      return const _MutedText('No query parameters');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in parameters.entries)
          _KeyValueRow(entry.key, entry.value.join(', ')),
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
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final labelWidth = constraints.maxWidth < 360 ? 88.0 : 112.0;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: labelWidth,
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SelectableText(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.35,
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
        border:
            Border.all(color: scheme.outlineVariant.withValues(alpha: 0.65)),
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
            Text('No network calls captured',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            const _MutedText('Make a Dio request and it will appear here.'),
          ],
        ),
      ),
    );
  }
}

Color _surfaceBase(BuildContext context) {
  return Theme.of(context).colorScheme.surface;
}

ThemeData _inspectorTheme(BuildContext context) {
  final parent = Theme.of(context);
  final isDark = parent.brightness == Brightness.dark;
  final seed = isDark ? const Color(0xFF5FD39A) : const Color(0xFF138A5B);
  final generated = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: parent.brightness,
  );
  final scheme = generated.copyWith(
    primary: seed,
    surface: isDark ? const Color(0xFF101613) : const Color(0xFFF7F9F8),
    surfaceContainerLowest:
        isDark ? const Color(0xFF151D19) : const Color(0xFFFFFFFF),
    surfaceContainerLow:
        isDark ? const Color(0xFF19221E) : const Color(0xFFF1F4F2),
    surfaceContainerHighest:
        isDark ? const Color(0xFF26312C) : const Color(0xFFE9EEEB),
    outlineVariant: isDark ? const Color(0xFF35433D) : const Color(0xFFDDE4E0),
  );

  final textTheme = parent.textTheme.apply(
    bodyColor: scheme.onSurface,
    displayColor: scheme.onSurface,
  );

  final base = ThemeData.from(
    colorScheme: scheme,
    textTheme: textTheme,
    useMaterial3: true,
  );

  return base.copyWith(
    platform: parent.platform,
    visualDensity: parent.visualDensity,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    textTheme: textTheme,
    dividerColor: scheme.outlineVariant,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surfaceContainerLowest,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: Border(bottom: BorderSide(color: scheme.outlineVariant)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
      hintStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    chipTheme: parent.chipTheme.copyWith(
      backgroundColor: Colors.transparent,
      selectedColor: scheme.primaryContainer,
      side: BorderSide(color: scheme.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      labelStyle: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      padding: const EdgeInsets.symmetric(horizontal: 4),
    ),
    tabBarTheme: parent.tabBarTheme.copyWith(
      indicatorColor: scheme.primary,
      labelColor: scheme.primary,
      unselectedLabelColor: scheme.onSurfaceVariant,
      dividerColor: scheme.outlineVariant,
      labelStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}

bool _isSlow(VigilHttpCall call) {
  final duration = call.duration;
  return duration != null && duration.inMilliseconds >= 1000;
}

Color _warningColor(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFFFFC45B)
      : const Color(0xFFB86B00);
}

String _formatDuration(Duration duration) {
  final milliseconds = duration.inMilliseconds;
  if (milliseconds < 1000) return '$milliseconds ms';
  final seconds = milliseconds / 1000;
  return '${seconds.toStringAsFixed(seconds >= 10 ? 1 : 2)} s';
}

String _pathOnly(Uri uri) {
  return uri.path.isEmpty ? '/' : uri.path;
}

Future<void> _copyWithFeedback(
  BuildContext context,
  String value,
  String message,
) async {
  await Clipboard.setData(ClipboardData(text: value));
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
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

Future<void> _shareLifecycle(
  BuildContext context,
  VigilHttpCall call,
) async {
  final renderObject = context.findRenderObject();
  final sharePositionOrigin = renderObject is RenderBox && renderObject.hasSize
      ? renderObject.localToGlobal(Offset.zero) & renderObject.size
      : null;

  try {
    await SharePlus.instance.share(
      ShareParams(
        text: _lifecycleJson(call),
        subject: 'Vigil request lifecycle: '
            '${call.request.method.toUpperCase()} ${_pathOnly(call.request.uri)}',
        title: 'Vigil request lifecycle',
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Unable to open the share sheet'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}

String _lifecycleJson(VigilHttpCall call) {
  final request = call.request;
  final response = call.response;
  final error = call.error;

  return const JsonEncoder.withIndent('  ').convert({
    'format': 'vigil-request-lifecycle',
    'version': 1,
    'id': call.id,
    'state': call.state.name,
    'startedAt': call.startedAt.toUtc().toIso8601String(),
    'completedAt': call.completedAt?.toUtc().toIso8601String(),
    'durationMs': call.duration == null
        ? null
        : call.duration!.inMicroseconds / Duration.microsecondsPerMillisecond,
    'trace': {
      'traceparent': request.traceContext.toHeader(),
      'traceId': request.traceContext.traceId,
      'parentId': request.traceContext.parentId,
      'flags': request.traceContext.flags,
    },
    'request': {
      'method': request.method,
      'url': request.uri.toString(),
      'headers': request.headers,
      'body': request.body.toJson(),
      'timestamp': request.timestamp.toUtc().toIso8601String(),
    },
    'response': response == null
        ? null
        : {
            'statusCode': response.statusCode,
            'statusMessage': response.statusMessage,
            'headers': response.headers,
            'body': response.body.toJson(),
            'timestamp': response.timestamp.toUtc().toIso8601String(),
            'serverTimings': response.serverTimings
                .map((timing) => timing.toJson())
                .toList(growable: false),
            'serverDebug': response.serverDebug?.toJson(),
          },
    'error': error == null
        ? null
        : {
            'message': error.message,
            'type': error.type,
            'stackTrace': error.stackTrace?.toString(),
            'timestamp': error.timestamp.toUtc().toIso8601String(),
          },
  });
}
