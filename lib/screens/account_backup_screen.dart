import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/account_backup_service.dart';
import '../services/auth_service.dart';
import '../utils/file_exporter.dart';

class AccountBackupScreen extends StatefulWidget {
  final AuthService? authService;
  final AccountBackupService? backupService;
  const AccountBackupScreen({super.key, this.authService, this.backupService});
  @override
  State<AccountBackupScreen> createState() => _AccountBackupScreenState();
}

class _AccountBackupScreenState extends State<AccountBackupScreen> {
  late final AuthService _auth = widget.authService ?? AuthService();
  late final AccountBackupService _service =
      widget.backupService ?? AccountBackupService();
  StreamSubscription<dynamic>? _subscription;
  String? _uid, _pending;
  AccountRestorePreview? _preview;
  List<String> _recoveries = [];
  bool _busy = false;
  String _message = '';
  @override
  void initState() {
    super.initState();
    _uid = _auth.currentUser?.uid;
    _subscription = _auth.authStateChanges.listen((user) {
      if (mounted && _uid != user?.uid) {
        setState(() {
          _uid = user?.uid;
          _pending = null;
          _preview = null;
          _recoveries = [];
          _message = '';
        });
        _load();
      }
    });
    _load();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  bool _active(String uid) =>
      mounted && _uid == uid && _auth.currentUser?.uid == uid;
  Future<void> _load() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final recoveries = await _service.getRecoveryIds(uid);
      if (_active(uid)) setState(() => _recoveries = recoveries);
    } catch (_) {
      if (_active(uid)) {
        setState(() => _message = 'Recovery history could not be loaded.');
      }
    }
  }

  Future<void> _export() async {
    final uid = _uid;
    if (uid == null || _busy) return;
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      final text = await _service.exportAccount(uid);
      if (_active(uid)) {
        await saveTextFile('personal-tax-account-backup.json', text);
      }
    } catch (_) {
      if (_active(uid)) {
        setState(
          () =>
              _message = 'Backup failed or sources changed. Reload and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _select() async {
    final uid = _uid;
    if (uid == null || _busy) return;
    setState(() {
      _busy = true;
      _message = '';
      _pending = null;
      _preview = null;
    });
    try {
      final selection = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (!_active(uid) || selection == null) return;
      final bytes = selection.files.single.bytes;
      if (bytes == null || bytes.length > 100000000) {
        throw const FormatException();
      }
      final text = utf8.decode(bytes);
      final preview = AccountBackupService.validate(
        Map<String, dynamic>.from(jsonDecode(text) as Map),
        uid,
      );
      if (_active(uid)) {
        setState(() {
          _preview = preview;
          _pending = text;
        });
      }
    } catch (_) {
      if (_active(uid)) {
        setState(
          () => _message =
              'Invalid, incomplete, unsupported or wrong-owner account backup.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final uid = _uid, text = _pending;
    if (uid == null || text == null || _busy) return;
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      await _service.restoreAccount(uid, text);
      if (_active(uid)) {
        setState(() {
          _message =
              'Recovered source drafts and complete historical evidence. Review every source and reselect sale parcels before calculating.';
          _pending = null;
          _preview = null;
        });
      }
      await _load();
    } catch (error) {
      if (_active(uid)) {
        setState(
          () => _message = error is StateError
              ? error.message.toString()
              : 'Recovery could not finish. Re-select the same backup to retry; existing facts are never overwritten.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _evidence(String hash) async {
    final uid = _uid;
    if (uid == null || _busy) return;
    setState(() => _busy = true);
    try {
      final evidence = await _service.getRecoveryEvidence(uid, hash);
      if (mounted && _active(uid)) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Recovered history and parcel selections'),
            content: SizedBox(
              width: 720,
              height: 500,
              child: StreamBuilder(
                stream: _auth.authStateChanges,
                initialData: _auth.currentUser,
                builder: (context, snapshot) => SingleChildScrollView(
                  child: SelectableText(
                    snapshot.data?.uid == uid
                        ? const JsonEncoder.withIndent('  ').convert(evidence)
                        : 'Sign in as the original owner to view this evidence.',
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } catch (_) {
      if (_active(uid)) {
        setState(() => _message = 'Recovery evidence could not be loaded.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Account backup and recovery')),
    body: _uid == null
        ? const Center(child: Text('Sign in to access account backups.'))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Export rental, investment, fund and tax-year records, parser mappings, properties and all retained revisions and snapshots. PDF files and authentication information are excluded.',
                ),
                const SizedBox(height: 16),
                const Text(
                  'Recovery requires the same owner and an empty account dataset. Sources reopen as unreviewed drafts. Original allocations, I1 decisions and final reports remain accessible as historical evidence; review and recalculate before finalising.',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton(
                      onPressed: _busy ? null : _export,
                      child: const Text('Download full account backup'),
                    ),
                    OutlinedButton(
                      onPressed: _busy ? null : _select,
                      child: const Text('Select recovery file'),
                    ),
                  ],
                ),
                if (_preview != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    '${_preview!.recordCount} historical records; ${_preview!.transactions} transactions; ${_preview!.funds} fund statements; ${_preview!.years} tax years; ${_preview!.items} manual sources.',
                  ),
                  FilledButton(
                    onPressed: _busy ? null : _restore,
                    child: const Text('Recover into empty account'),
                  ),
                ],
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ),
                if (_message.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(_message),
                  ),
                for (final id in _recoveries)
                  ListTile(
                    title: const Text('Recovered source history'),
                    subtitle: Text(id),
                    trailing: const Icon(Icons.history),
                    onTap: _busy ? null : () => _evidence(id),
                  ),
              ],
            ),
          ),
  );
}
