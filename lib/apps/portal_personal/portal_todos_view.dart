import 'package:flutter/material.dart';

import '../../capabilities/east8_time.dart';
import '../../services/user_error_message.dart';
import '../tronclass/tronclass_models.dart';
import '../tronclass/tronclass_service.dart';

typedef PortalTodosLoader =
    Future<List<TronclassTodo>> Function({required bool force});

/// 课程待办视图：展示畅课待办列表（供“个人数据”使用）。
class PortalTodosView extends StatefulWidget {
  final PortalTodosLoader? loader;

  final bool active;

  const PortalTodosView({super.key, this.loader, this.active = true});

  @override
  State<PortalTodosView> createState() => _PortalTodosViewState();
}

class _PortalTodosViewState extends State<PortalTodosView>
    with AutomaticKeepAliveClientMixin {
  List<TronclassTodo>? _todos;
  String? _error;
  bool _loading = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (widget.active) _load();
  }

  @override
  void didUpdateWidget(covariant PortalTodosView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active && _todos == null && !_loading) {
      _load();
    }
  }

  Future<void> _load({bool force = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final loader = widget.loader;
      final todos =
          loader == null
              ? await TronclassService().fetchTodos(force: force)
              : await loader(force: force);
      if (!mounted) return;
      setState(() {
        _todos = todos;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      if (widget.active) {
        logUserFacingError(UserErrorContext.network, error, operation: 'todos');
      }
      setState(() {
        _error = userFacingError(UserErrorContext.network, error);
        _loading = false;
      });
    }
  }

  Future<void> _retry() => _load(force: true);

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return _buildMaterial();
  }

  Widget _buildMaterial() {
    final todos = _todos;
    if (_loading && todos == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && todos == null) {
      return _ErrorState(message: _error!, onRetry: _retry);
    }
    if (todos == null || todos.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _load(force: true),
        child: const _EmptyState(
          icon: Icons.checklist_outlined,
          message: '暂无待办',
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(force: true),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: todos.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) => _TodoCard(todo: todos[index]),
      ),
    );
  }
}

class _TodoCard extends StatelessWidget {
  final TronclassTodo todo;

  const _TodoCard({required this.todo});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final deadline = todo.endTime;
    final overdue = deadline != null && deadline.isBefore(east8Now());
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    todo.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _TypeChip(type: todo.type),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              todo.courseName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  overdue ? Icons.event_busy_outlined : Icons.schedule_outlined,
                  size: 16,
                  color: overdue ? colors.error : colors.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    deadline == null
                        ? '无截止时间'
                        : '截止时间 ${_formatDateTime(deadline)}'
                            '${overdue ? '（已截止）' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: overdue ? colors.error : colors.onSurfaceVariant,
                    ),
                  ),
                ),
                if (todo.isLocked)
                  Icon(
                    Icons.lock_outline,
                    size: 16,
                    color: colors.onSurfaceVariant,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String type;

  const _TypeChip({required this.type});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final label = _todoTypeLabel(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colors.onSecondaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 48, color: colors.error),
            const SizedBox(height: 12),
            Text(
              message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            children: [
              Icon(icon, size: 56, color: colors.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _todoTypeLabel(String type) => switch (type) {
  'homework' => '作业',
  'exam' => '考试',
  'vote' => '投票',
  'discussion' => '讨论',
  _ => type.isEmpty ? '任务' : type,
};

String _formatDateTime(DateTime time) {
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${time.year}-${pad(time.month)}-${pad(time.day)} '
      '${pad(time.hour)}:${pad(time.minute)}';
}
