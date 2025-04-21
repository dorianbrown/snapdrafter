import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '/utils/data.dart';

class BackupSettings extends StatefulWidget {
  const BackupSettings({Key? key}) : super(key: key);

  @override
  State<BackupSettings> createState() => _BackupSettingsState();
}

class _BackupSettingsState extends State<BackupSettings> {
  late DeckStorage deckStorage;
  bool isBackingUp = false;
  bool isRestoring = false;
  String? backupStatus;
  int? deckCount;

  @override
  void initState() {
    super.initState();
    deckStorage = DeckStorage();
    _loadDeckCount();
  }

  Future<void> _loadDeckCount() async {
    final decks = await deckStorage.getAllDecks();
    setState(() {
      deckCount = decks.length;
    });
  }

  Future<void> _createBackup() async {
    setState(() {
      isBackingUp = true;
      backupStatus = null;
    });

    try {
      final backup = await deckStorage.createBackupData();
      final jsonString = jsonEncode(backup);
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/mtg_backup_${DateTime.now().millisecondsSinceEpoch}.json');
      await file.writeAsString(jsonString);

      setState(() {
        backupStatus = 'Backup created successfully!\nLocation: ${file.path}';
      });
    } catch (e) {
      setState(() {
        backupStatus = 'Backup failed: ${e.toString()}';
      });
    } finally {
      setState(() => isBackingUp = false);
    }
  }

  Future<void> _restoreBackup() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (result == null) return;

    setState(() {
      isRestoring = true;
      backupStatus = null;
    });

    try {
      final file = File(result.files.single.path!);
      final jsonString = await file.readAsString();
      final backupData = jsonDecode(jsonString);

      await deckStorage.restoreBackup(backupData);
      await _loadDeckCount();

      setState(() {
        backupStatus = 'Restore completed successfully!';
      });
    } catch (e) {
      setState(() {
        backupStatus = 'Restore failed: ${e.toString()}';
      });
    } finally {
      setState(() => isRestoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Backup Settings')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (deckCount != null)
              Text('Current decks: $deckCount', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: isBackingUp 
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.backup),
                label: const Text('Create Backup'),
                onPressed: isBackingUp ? null : _createBackup,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: isRestoring
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.restore),
                label: const Text('Restore Backup'),
                onPressed: isRestoring ? null : _restoreBackup,
              ),
            ),
            const SizedBox(height: 20),
            if (backupStatus != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  backupStatus!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
