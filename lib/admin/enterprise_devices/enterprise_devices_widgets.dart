part of 'enterprise_devices_screen.dart';

// ---------------------------------------------------------------- shared UI

class _Loader<T> extends StatefulWidget {
  const _Loader({
    super.key,
    required this.load,
    required this.builder,
    this.isEmpty,
    this.empty,
  });
  final Future<T> Function() load;
  final Widget Function(T data, VoidCallback reload) builder;
  final bool Function(T data)? isEmpty;
  final Widget? empty;
  @override
  State<_Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<_Loader<T>> {
  late Future<T> future = widget.load();
  void reload() => setState(() => future = widget.load());
  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: future,
        builder: (BuildContext context, AsyncSnapshot<T> snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const _Skeleton();
          }
          if (snap.hasError) {
            return _ErrorBox(error: snap.error!, onRetry: reload);
          }
          final T data = snap.data as T;
          if (widget.isEmpty?.call(data) == true) {
            return widget.empty ?? const SizedBox();
          }
          return widget.builder(data, reload);
        },
      );
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();
  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Loading',
        child: Column(
          children: List<Widget>.generate(
            5,
            (int i) => Container(
              height: i == 0 ? 56 : 38,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFE3EAE4),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
      );
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    final bool prov = error is EnterpriseDevicesException &&
        (error as EnterpriseDevicesException).provisioningRequired;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: prov ? const Color(0xFFFFF7E6) : const Color(0xFFFDECEA),
        border: Border.all(color: prov ? EdColors.amber : EdColors.red),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            prov ? Icons.construction_outlined : Icons.error_outline,
            color: prov ? EdColors.amber : EdColors.red,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  prov ? 'Provisioning required' : 'Request failed',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: EdColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text('$error', style: const TextStyle(color: EdColors.ink)),
                if (onRetry != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.icon,
    required this.title,
    required this.text,
    this.action,
  });
  final IconData icon;
  final String title;
  final String text;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(
                  color: EdColors.greenSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: EdColors.forest, size: 28),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: EdColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: EdColors.muted),
              ),
              if (action != null) action!,
            ],
          ),
        ),
      );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFFCFDFB),
          border: Border.all(color: EdColors.line),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: EdColors.line)),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      title.toUpperCase(),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 11.5,
                        letterSpacing: 1,
                        color: EdColors.forest,
                      ),
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
            Padding(padding: const EdgeInsets.all(14), child: child),
          ],
        ),
      );
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg) = switch (status) {
      'AVAILABLE' => (EdColors.greenSoft, EdColors.forest),
      'ASSIGNED' => (const Color(0xFFE4EEFA), const Color(0xFF1D4E89)),
      'INACTIVE' => (const Color(0xFFEDEFEC), EdColors.muted),
      'LOST_STOLEN' => (const Color(0xFFFDECEA), EdColors.red),
      'RETIRED' => (const Color(0xFFF4EFE6), const Color(0xFF7A5A1E)),
      _ => (const Color(0xFFEDEFEC), EdColors.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        status.replaceAll('_', ' / '),
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w800,
          fontSize: 10.5,
          letterSpacing: .5,
        ),
      ),
    );
  }
}

void _toast(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(msg),
      backgroundColor: error ? EdColors.red : EdColors.forest,
    ),
  );
}

String _err(Object e) => '$e'.replaceFirst('Exception: ', '');
