part of 'revenue_account_screen.dart';

class _KpiData {
  const _KpiData(this.label, this.value, this.note, this.icon, this.color);
  final String label;
  final String value;
  final String note;
  final IconData icon;
  final Color color;
}

class _RevenueSkeleton extends StatelessWidget {
  const _RevenueSkeleton();
  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(20),
        children: List<Widget>.generate(
          7,
          (int index) => Container(
            height: index == 0 ? 70 : 78,
            margin: const EdgeInsets.only(bottom: 11),
            decoration: BoxDecoration(
              color: const Color(0xffe7ece8),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            const Icon(Icons.cloud_off_outlined,
                size: 38, color: Color(0xffa9423d)),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry')),
          ]),
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.message});
  final String title;
  final String message;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            const Icon(Icons.query_stats_outlined,
                size: 29, color: Color(0xff9aa69f)),
            const SizedBox(height: 7),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Color(0xff43564d), fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xff7c8983), fontSize: 11)),
          ]),
        ),
      );
}
