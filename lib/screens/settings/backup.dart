import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:snapdrafter/data/database/database_helper.dart';

import '/utils/deck_change_notifier.dart';
import '/data/repositories/deck_repository.dart';
import '/data/repositories/cube_repository.dart';
import '/data/database/backup_helper.dart';

class BackupSettings extends StatefulWidget {
  const BackupSettings({Key? key}) : super(key: key);

  @override
  State<BackupSettings> createState() => _BackupSettingsState();
}

class _BackupSettingsState extends State<BackupSettings> {
  late DeckRepository deckRepository;
  late CubeRepository cubeRepository;
  late BackupHelper backupHelper;
  bool isBackingUp = false;
  bool isRestoring = false;
  String? backupStatus;
  int? deckCount;
  int? cubeCount;

  final DeckChangeNotifier _notifier = DeckChangeNotifier();

  @override
  void initState() {
    super.initState();
    deckRepository = DeckRepository();
    cubeRepository = CubeRepository();
    backupHelper = BackupHelper();
    _loadDeckCount();
  }

  Future<void> _loadDeckCount() async {
    final decks = await deckRepository.getAllDecks();
    final cubes = await cubeRepository.getAllCubes();
    setState(() {
      deckCount = decks.length;
      cubeCount = cubes.length;
    });
  }

  Future<void> _createBackup() async {
    setState(() {
      isBackingUp = true;
      backupStatus = null;
    });

    try {
      final backup = await backupHelper.createBackupData();
      final jsonString = jsonEncode(backup);
      Directory? directory;
      if (Platform.isIOS) {
        directory = await getApplicationDocumentsDirectory();
      } else {
        directory = Directory('/storage/emulated/0/Download');
        if (!await directory.exists()) directory = await getExternalStorageDirectory();
      }
      DateTime timestamp = DateTime.now();
      String datetimeString = "${timestamp.year}${timestamp.month}${timestamp.day}_${timestamp.hour}${timestamp.minute}${timestamp.second}";
      final file = File('${directory!.path}/snapdrafter_backup_$datetimeString.json');
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

      await backupHelper.restoreBackup(backupData);
      await _loadDeckCount();

      setState(() {
        backupStatus = 'Restore completed successfully!';
      });
    } catch (e) {
      setState(() {
        backupStatus = 'Restore failed: ${e.toString()}';
      });
    } finally {
      _notifier.markNeedsRefresh();
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
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            if (deckCount != null)
              Text('Current decks: $deckCount\nCurrent cubes: $cubeCount', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 15,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.backup),
                  label: const Text('Create Backup'),
                  onPressed: isBackingUp ? null : _createBackup,
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.restore),
                  label: const Text('Restore Backup'),
                  onPressed: isRestoring ? null : _restoreBackup,
                )
              ]
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
