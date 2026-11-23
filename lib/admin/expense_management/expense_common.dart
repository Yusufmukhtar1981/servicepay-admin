import 'package:flutter/material.dart';

import 'expense_api.dart';

// Existing Financial Control palette (Admin established styles).
const Color expInk = Color(0xff173e35);
const Color expGreen = Color(0xff176b58);
const Color expPaper = Color(0xfff3f7f4);
const Color expLine = Color(0xffdce7e1);
const Color expMuted = Color(0xff61756c);
const Color expSoft = Color(0xffe8f0eb);
const Color expCard = Color(0xfffbfcfa);
const Color expDanger = Color(0xff9b403b);
const Color expAmber = Color(0xff8a641c);

/// Exact backend permission strings (expenseManagement.rules.js).
abstract final class ExpensePermissions {
  static const String view = 'expenses.view';
  static const String create = 'expenses.create';
  static const String update = 'expenses.update';
  static const String approve = 'expenses.approve';
  static const String pay = 'expenses.pay';
  static const String categories = 'expenses.manage_categories';
  static const String vendors = 'expenses.manage_vendors';
  static const String policy = 'expenses.manage_policy';
  static const String documents = 'expenses.documents';
  static const String audit = 'expenses.audit';
  static const String export = 'expenses.export';
  static const String cancel = 'expenses.cancel';
  static const String exception = 'expenses.evidence_exception';

  static const Map<String, String> labels = <String, String>{
    view: 'View expenses',
    create: 'Create expenses',
    update: 'Edit expenses',
    approve: 'Approve expenses',
    pay: 'Record payments',
    categories: 'Manage categories',
    vendors: 'Manage vendors',
    policy: 'Manage approval policy',
    documents: 'Download documents',
    audit: 'View audit logs',
    export: 'Export reports',
    cancel: 'Cancel / reverse expenses',
    exception: 'Authorize evidence exceptions',
  };
}

/// Access derived ONLY from the exact permission list returned by
/// GET /readiness. Wildcards and broad Head Office roles never count.
class ExpenseAccess {
  ExpenseAccess({required Iterable<String> permissions, this.role = '', this.actorId = ''})
      : permissions = permissions
            .map((String p) => p.trim().toLowerCase())
            .where((String p) => p.startsWith('expenses.'))
            .toSet();

  factory ExpenseAccess.fromReadiness(Map<String, dynamic> data) {
    final Map<String, dynamic> actor = asMap(data['actor']);
    return ExpenseAccess(
      permissions: asList(data['permissions']).map((dynamic v) => '$v'),
      role: text(actor['role']).toUpperCase().replaceAll(RegExp(r'[\s-]+'), '_'),
      actorId: text(actor['id']),
    );
  }

  final Set<String> permissions;
  final String role;
  final String actorId;

  bool has(String permission) => permissions.contains(permission);
  bool get canManagePolicy =>
      has(ExpensePermissions.policy) && role == 'HEAD_OFFICE';
}

Map<String, dynamic> asMap(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<dynamic> asList(dynamic v) => v is List ? List<dynamic>.from(v) : <dynamic>[];
String text(dynamic v, {String fallback = ''}) {
  final String s = v?.toString().trim() ?? '';
  return s.isEmpty ? fallback : s;
}

int? asInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v'));

String groupDigits(String digits) {
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// Formats integer kobo. Returns 'Unavailable' for null so missing data is
/// never shown as zero.
String money(dynamic minor, {String currency = 'NGN'}) {
  final int? value = asInt(minor);
  if (value == null) return 'Unavailable';
  final bool negative = value < 0;
  final int abs = value.abs();
  final String whole = groupDigits('${abs ~/ 100}');
  final String fraction = (abs % 100).toString().padLeft(2, '0');
  return '${negative ? '-' : ''}$currency $whole.$fraction';
}

/// Converts kobo to an editable decimal string for the form.
String minorToDecimal(dynamic minor) {
  final int? v = asInt(minor);
  if (v == null) return '';
  final int frac = v % 100;
  return frac == 0 ? '${v ~/ 100}' : '${v ~/ 100}.${frac.toString().padLeft(2, '0')}';
}

String count(dynamic v) {
  final int? n = asInt(v);
  return n == null ? 'Unavailable' : groupDigits('$n');
}

DateTime lagosToday() {
  final DateTime t = DateTime.now().toUtc().add(const Duration(hours: 1));
  return DateTime(t.year, t.month, t.day);
}

String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? parseYmd(String s) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return null;
  final DateTime? d = DateTime.tryParse(s);
  return d != null && ymd(d) == s ? d : null;
}

String timestamp(dynamic v) {
  final DateTime? d = DateTime.tryParse(text(v));
  if (d == null) return text(v, fallback: '—');
  final DateTime l = d.toUtc().add(const Duration(hours: 1));
  return '${ymd(l)} ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')} WAT';
}

String errorText(Object e) => e is ExpenseApiException
    ? e.message
    : 'Something went wrong. Your input is preserved; try again.';

const Map<String, String> paymentMethods = <String, String>{
  'BANK_TRANSFER': 'Bank transfer',
  'CASH': 'Cash',
  'POS': 'POS',
  'CARD': 'Card',
  'CHEQUE': 'Cheque',
  'OTHER': 'Other',
};

const Map<String, String> statusLabels = <String, String>{
  'SUBMITTED': 'Submitted',
  'PENDING_APPROVAL': 'Pending approval',
  'APPROVED': 'Approved',
  'REJECTED': 'Rejected',
  'PAID': 'Paid (recorded)',
  'CANCELLED': 'Cancelled',
  'REVERSED': 'Reversed',
};

// ---------------- Shared widgets ----------------

class ExpenseStatusChip extends StatelessWidget {
  const ExpenseStatusChip(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg) = switch (status) {
      'APPROVED' => (const Color(0xffdcefe5), expGreen),
      'PAID' => (const Color(0xffcfe6dc), expInk),
      'REJECTED' || 'REVERSED' => (const Color(0xfff6e1df), expDanger),
      'CANCELLED' => (const Color(0xffeceeed), const Color(0xff56625d)),
      'PENDING_APPROVAL' => (const Color(0xfffff4de), expAmber),
      _ => (expSoft, const Color(0xff466158)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5)),
      child: Text(statusLabels[status] ?? status,
          style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w800)),
    );
  }
}

class ExpensePanel extends StatelessWidget {
  const ExpensePanel({super.key, required this.title, this.subtitle, required this.child, this.trailing});
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: expCard,
          border: Border.all(color: expLine),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: <Widget>[
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text(title, style: const TextStyle(color: expInk, fontWeight: FontWeight.w800, fontSize: 15)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(subtitle!, style: const TextStyle(color: expMuted, fontSize: 12)),
                  ),
              ]),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ]),
      );
}

class ExpenseNotice extends StatelessWidget {
  const ExpenseNotice(this.message, {super.key, this.tone = 'info', this.icon});
  final String message;
  final String tone;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final bool error = tone == 'error';
    final bool warn = tone == 'warn';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: error ? const Color(0xfff8e7e5) : warn ? const Color(0xfffff4de) : expSoft,
        border: Border.all(color: error ? const Color(0xffe5bfbb) : warn ? const Color(0xffead5a9) : expLine),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Icon(icon ?? (error ? Icons.error_outline : warn ? Icons.warning_amber_outlined : Icons.info_outline),
            size: 19, color: error ? expDanger : warn ? expAmber : expGreen),
        const SizedBox(width: 9),
        Expanded(
          child: SelectableText(message,
              style: TextStyle(
                  color: error ? expDanger : warn ? const Color(0xff6d5524) : const Color(0xff3f5a51),
                  fontSize: 12.5,
                  height: 1.35,
                  fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

class ExpenseErrorState extends StatelessWidget {
  const ExpenseErrorState({super.key, required this.message, required this.onRetry, this.retryLabel = 'Reload'});
  final String message;
  final VoidCallback onRetry;
  final String retryLabel;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ExpenseNotice(message, tone: 'error'),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(retryLabel),
          ),
        ],
      );
}

class ExpenseEmptyState extends StatelessWidget {
  const ExpenseEmptyState({super.key, required this.title, required this.message, this.icon = Icons.receipt_long_outlined, this.action});
  final String title;
  final String message;
  final IconData icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
        decoration: BoxDecoration(
          border: Border.all(color: expLine),
          borderRadius: BorderRadius.circular(9),
          color: expCard,
        ),
        child: Column(children: <Widget>[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(color: expSoft, shape: BoxShape.circle),
            child: Icon(icon, color: expGreen, size: 26),
          ),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(color: expInk, fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 5),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: expMuted, fontSize: 12.5, height: 1.35)),
          if (action != null) ...<Widget>[const SizedBox(height: 14), action!],
        ]),
      );
}

/// Skeleton blocks used instead of spinners.
class ExpenseSkeleton extends StatelessWidget {
  const ExpenseSkeleton({super.key, this.rows = 4});
  final int rows;
  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Loading',
        child: Column(
          children: List<Widget>.generate(
            rows,
            (int i) => Container(
              height: i == 0 ? 74 : 48,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: i.isEven ? const Color(0xffe4ece7) : const Color(0xffebf1ed),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      );
}

class ExpenseField extends StatelessWidget {
  const ExpenseField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.validator,
    this.maxLines = 1,
    this.keyboardType,
    this.helper,
    this.fieldKey,
    this.enabled = true,
    this.maxLength,
  });
  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? helper;
  final FormFieldValidator<String>? validator;
  final int maxLines;
  final TextInputType? keyboardType;
  final Key? fieldKey;
  final bool enabled;
  final int? maxLength;
  @override
  Widget build(BuildContext context) => TextFormField(
        key: fieldKey,
        controller: controller,
        enabled: enabled,
        validator: validator,
        maxLines: maxLines,
        minLines: maxLines > 1 ? 2 : 1,
        maxLength: maxLength,
        keyboardType: keyboardType,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        decoration: expInput(label, hint: hint, helper: helper),
      );
}

InputDecoration expInput(String label, {String? hint, String? helper}) => InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      helperMaxLines: 3,
      errorMaxLines: 3,
      isDense: true,
      filled: true,
      fillColor: const Color(0xfff8faf8),
      border: const OutlineInputBorder(),
      contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 12),
    );

String? requiredText(String? v, String label, {int max = 200, int min = 1}) {
  final String s = v?.trim() ?? '';
  if (s.isEmpty) return '$label is required.';
  if (s.length < min) return '$label needs at least $min characters.';
  if (s.length > max) return '$label must be $max characters or fewer.';
  return null;
}

final RegExp amountPattern = RegExp(r'^(?:0|[1-9]\d{0,13})(?:\.\d{1,2})?$');

String? amountValidator(String? v) {
  final String s = (v ?? '').trim().replaceAll(',', '');
  if (s.isEmpty) return 'Amount is required.';
  if (!amountPattern.hasMatch(s)) return 'Enter a positive NGN amount with at most two decimals, e.g. 125000.50';
  if (RegExp(r'^0(?:\.0{1,2})?$').hasMatch(s)) return 'Amount must be greater than zero.';
  return null;
}

/// Displays a reason dialog. Controller lifetime is owned by the dialog
/// state so it survives the exit animation.
Future<String?> askReason(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  int minLength = 10,
  bool destructive = false,
}) =>
    showDialog<String>(
      context: context,
      builder: (BuildContext context) => _ReasonDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        minLength: minLength,
        destructive: destructive,
      ),
    );

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title, required this.message, required this.confirmLabel, required this.minLength, required this.destructive});
  final String title;
  final String message;
  final String confirmLabel;
  final int minLength;
  final bool destructive;
  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final TextEditingController _reason = TextEditingController();
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: 460,
          child: Form(
            key: _form,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text(widget.message, style: const TextStyle(color: expMuted, height: 1.35)),
                const SizedBox(height: 12),
                ExpenseField(
                  fieldKey: const Key('reason-field'),
                  controller: _reason,
                  label: 'Reason (recorded in audit log)',
                  maxLines: 3,
                  validator: (String? v) => requiredText(v, 'Reason', max: 2000, min: widget.minLength),
                ),
              ]),
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Go back')),
          FilledButton(
            key: const Key('reason-confirm'),
            style: FilledButton.styleFrom(backgroundColor: widget.destructive ? expDanger : expGreen),
            onPressed: () {
              if (_form.currentState!.validate()) Navigator.pop(context, _reason.text.trim());
            },
            child: Text(widget.confirmLabel),
          ),
        ],
      );
}

void showExpenseMessage(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: error ? expDanger : expGreen,
  ));
}

/// Shared horizontal-scrolling dense table.
class ExpenseTable extends StatelessWidget {
  const ExpenseTable({super.key, required this.headers, required this.rows, this.onTap});
  final List<String> headers;
  final List<List<Widget>> rows;
  final void Function(int index)? onTap;
  @override
  Widget build(BuildContext context) => Scrollbar(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 38,
            dataRowMinHeight: 42,
            dataRowMaxHeight: 64,
            columnSpacing: 22,
            showCheckboxColumn: false,
            headingTextStyle: const TextStyle(color: Color(0xff687b73), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.4),
            dataTextStyle: const TextStyle(color: expInk, fontSize: 12.5),
            columns: headers.map((String h) => DataColumn(label: Text(h.toUpperCase()))).toList(),
            rows: <DataRow>[
              for (int i = 0; i < rows.length; i++)
                DataRow(
                  onSelectChanged: onTap == null ? null : (_) => onTap!(i),
                  cells: rows[i].map((Widget w) => DataCell(w)).toList(),
                ),
            ],
          ),
        ),
      );
}
