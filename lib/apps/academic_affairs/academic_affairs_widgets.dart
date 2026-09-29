import 'package:flutter/material.dart';

import 'academic_affairs_models.dart';
import '../../services/user_error_message.dart';
import '../../services/academic_affairs_backend.dart';

/// 考试安排 / 成绩查询页面共享的加载/错误/空态与细节组件。
class AcademicSectionResult<T> {
  final T? value;
  final Object? error;

  const AcademicSectionResult({this.value, this.error});
}

Future<AcademicSectionResult<T>> captureAcademicSection<T>(
  Future<T> Function() loader,
) async {
  try {
    return AcademicSectionResult(value: await loader());
  } catch (error) {
    return AcademicSectionResult(error: error);
  }
}

class AcademicSectionFallback extends StatelessWidget {
  final bool loading;
  final Object? error;
  final String emptyMessage;
  final Future<void> Function() onRefresh;

  const AcademicSectionFallback({
    super.key,
    required this.loading,
    required this.error,
    required this.emptyMessage,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error == null) {
      return AcademicEmptyState(message: emptyMessage, onRefresh: onRefresh);
    }
    return AcademicErrorState(error: error!, onRetry: onRefresh);
  }
}

class AcademicErrorState extends StatelessWidget {
  final Object error;
  final Future<void> Function() onRetry;

  const AcademicErrorState({
    super.key,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 48),
            const SizedBox(height: 12),
            Text(academicErrorMessage(error), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重新加载'),
            ),
          ],
        ),
      ),
    );
  }
}

class AcademicInlineError extends StatelessWidget {
  final Object error;
  final Future<void> Function() onRetry;

  const AcademicInlineError({
    super.key,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: ListTile(
        leading: Icon(
          Icons.error_outline,
          color: Theme.of(context).colorScheme.onErrorContainer,
        ),
        title: Text(academicErrorMessage(error)),
        trailing: TextButton(onPressed: onRetry, child: const Text('重试')),
      ),
    );
  }
}

class AcademicEmptyState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRefresh;

  const AcademicEmptyState({
    super.key,
    required this.message,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AcademicEmptyCard(
        icon: Icons.inbox_outlined,
        text: message,
        action: TextButton(onPressed: onRefresh, child: const Text('刷新')),
      ),
    );
  }
}

class AcademicEmptyCard extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;

  const AcademicEmptyCard({
    super.key,
    required this.icon,
    required this.text,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final child = Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40),
          const SizedBox(height: 8),
          Text(text, textAlign: TextAlign.center),
          if (action != null) action!,
        ],
      ),
    );

    return Card(child: child);
  }
}

class AcademicDetailChip extends StatelessWidget {
  final String label;
  final String value;

  const AcademicDetailChip({
    super.key,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('$label：$value', style: null),
    );
  }
}

String academicValue(String value) => value.isEmpty ? '—' : value;

String? defaultSemesterId(List<AcademicSemesterOption> options) {
  for (final option in options) {
    if (option.selected) return option.id;
  }
  return options.isEmpty ? null : options.first.id;
}

String academicErrorMessage(Object error) {
  if (error is AcademicAffairsIdentityException) {
    return error.message;
  }
  if (error is AcademicAffairsAuthenticationException) {
    return '教务系统登录状态已失效，请重新登录后重试。';
  }
  return userFacingError(UserErrorContext.academic, error);
}
