import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'edupay_school_api.dart';

/// Public, staged school onboarding. Documents are represented by their
/// selected upload reference and are uploaded by the API in the final step.
class SchoolRegistrationScreen extends StatefulWidget {
  const SchoolRegistrationScreen({super.key, this.api, this.initialLogo,
    this.initialDocuments = const []});
  final EduPaySchoolApi? api;
  final PlatformFile? initialLogo;
  final List<PlatformFile> initialDocuments;
  @override
  State<SchoolRegistrationScreen> createState() => _SchoolRegistrationScreenState();
}

class _SchoolRegistrationScreenState extends State<SchoolRegistrationScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(), _email = TextEditingController();
  final _phone = TextEditingController(), _address = TextEditingController();
  final _registrationNumber = TextEditingController(), _contactPerson = TextEditingController();
  final _type = TextEditingController(), _state = TextEditingController();
  final _lga = TextEditingController(), _password = TextEditingController();
  final _bankName = TextEditingController(), _bankCode = TextEditingController();
  final _accountNumber = TextEditingController(), _accountName = TextEditingController();
  final _owner = TextEditingController();
  PlatformFile? _logo;
  late final List<PlatformFile> _documents = [...widget.initialDocuments];
  int step = 0;
  bool submitting = false;
  final _titles = const ['School details', 'Primary contact', 'Verification documents'];

  @override
  void initState() {
    super.initState();
    _logo = widget.initialLogo;
  }

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _address, _registrationNumber, _contactPerson,
      _type, _state, _lga, _password,
      _bankName, _bankCode, _accountNumber, _accountName, _owner]) {
      c.dispose();
    }
    super.dispose();
  }

  bool _next() {
    if (!_form.currentState!.validate()) return false;
    if (step < _titles.length - 1) {
      setState(() => step++);
      return false;
    }
    return true;
  }

  Future<void> _pickFile(bool logo) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: logo
          ? ['png', 'jpg', 'jpeg'] : ['png', 'jpg', 'jpeg', 'pdf'],
      withData: true);
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (bytes == null) return;
    final maxBytes = logo ? 2 * 1024 * 1024 : 10 * 1024 * 1024;
    if (bytes.length > maxBytes) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('This ${logo ? 'logo' : 'supporting document'} must be '
          '${logo ? '2 MB' : '10 MB'} or smaller.')));
      return;
    }
    setState(() {
      if (logo) {
        _logo = file;
      } else {
        _documents.add(file!);
      }
    });
  }

  Future<void> _submit() async {
    if (!_next()) return;
    if (_logo == null || _documents.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Logo and at least one supporting document are required.')));
      return;
    }
    setState(() => submitting = true);
    try {
      await (widget.api ?? EduPaySchoolApi()).applySchool(fields: {
        'name': _name.text.trim(), 'email': _email.text.trim(),
        'phone': _phone.text.trim(), 'address': _address.text.trim(),
        'registrationNumber': _registrationNumber.text.trim(),
        'contactPerson': _contactPerson.text.trim(),
        'schoolType': _type.text.trim(), 'state': _state.text.trim(), 'lga': _lga.text.trim(),
        'password': _password.text, 'bankName': _bankName.text.trim(),
        'bankCode': _bankCode.text.trim(), 'accountNumber': _accountNumber.text.trim(),
        'accountName': _accountName.text.trim(),
        'authorizedRepresentative': _owner.text.trim(),
      }, logo: _logo, supportingDocuments: _documents);
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (_) => AlertDialog(
        title: const Text('Application Submitted Successfully.'),
        content: const Text(
          'Application Submitted Successfully. Your school registration is being reviewed by Servicepay. You will be notified when it is approved.'),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
      ));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Widget _field(TextEditingController c, String label, {bool email = false,
    int? minLength, bool digitsOnly = false}) =>
      TextFormField(controller: c, keyboardType: email ? TextInputType.emailAddress : null,
        validator: (v) => v == null || v.trim().isEmpty ? '$label is required' :
          (email && !v.contains('@') ? 'Enter a valid email' :
            (minLength != null && v.trim().length < minLength ? '$label must be at least $minLength characters' :
              (digitsOnly && !RegExp(r'^\d{10}$').hasMatch(v.trim()) ? '$label must be exactly 10 digits' : null))),
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Register your school')),
    body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 620), child: Card(
        child: Padding(padding: const EdgeInsets.all(24), child: Form(key: _form, child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Register Your School', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8), Text('Step ${step + 1} of ${_titles.length}: ${_titles[step]}'),
            const SizedBox(height: 18), LinearProgressIndicator(value: (step + 1) / _titles.length),
            const SizedBox(height: 24),
            if (step == 0) ...[_field(_name, 'School name'), const SizedBox(height: 14),
              _field(_registrationNumber, 'Registration Number'), const SizedBox(height: 14),
              _field(_contactPerson, 'Contact Person'), const SizedBox(height: 14),
              _field(_type, 'School type'), const SizedBox(height: 14), _field(_address, 'School address'),
              const SizedBox(height: 14), _field(_state, 'State'), const SizedBox(height: 14), _field(_lga, 'LGA')],
            if (step == 1) ...[_field(_owner, 'Authorized representative'), const SizedBox(height: 14),
              _field(_email, 'Email', email: true), const SizedBox(height: 14), _field(_phone, 'Phone number')],
            if (step == 2) ...[_field(_password, 'Password', minLength: 6),
              const SizedBox(height: 14), _field(_bankName, 'Bank name'), const SizedBox(height: 14),
              _field(_bankCode, 'Bank code'), const SizedBox(height: 14), _field(_accountNumber, 'Account number', digitsOnly: true),
              const SizedBox(height: 14), _field(_accountName, 'Account name'), const SizedBox(height: 14),
              OutlinedButton.icon(onPressed: () => _pickFile(true), icon: const Icon(Icons.image_outlined),
                label: Text(_logo == null ? 'Choose logo (PNG/JPEG, max 2 MB)' : 'Logo selected')),
              OutlinedButton.icon(onPressed: () => _pickFile(false), icon: const Icon(Icons.upload_file),
                label: Text('Add supporting document (${_documents.length})')),
              const Text('Files are encoded securely for the application request.')],
            const SizedBox(height: 26), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              if (step > 0) TextButton(onPressed: submitting ? null : () => setState(() => step--), child: const Text('Back')),
              const Spacer(), FilledButton(onPressed: submitting ? null : (step == _titles.length - 1 ? _submit : _next),
                child: Text(step == _titles.length - 1 ? 'Submit application' : 'Continue')),
            ]),
          ],
        ))),
      )),
    )),
  );
}