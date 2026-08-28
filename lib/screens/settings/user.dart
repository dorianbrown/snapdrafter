import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserSettings extends StatefulWidget {
  const UserSettings({super.key});

  @override
  State<UserSettings> createState() => _UserSettingsState();
}

class _UserSettingsState extends State<UserSettings> {
  // Used for persistent storage of settings
  late SharedPreferences prefs;
  // Used to validate form
  final _formKey = GlobalKey<FormState>();
  final TextEditingController usernameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    initPreferences();
  }

  Future<void> initPreferences() async {
    prefs = await SharedPreferences.getInstance();
    usernameController.text = prefs.getString("username") ?? "";
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('User Settings'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: usernameController,
          autofocus: true,
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Please enter some text';
            }
            return null;
          },
          decoration: const InputDecoration(
            labelText: "Username",
            border: OutlineInputBorder(),
          ),
          onFieldSubmitted: (_) => _save(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Cancel"),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text("Save"),
        ),
      ],
    );
  }

  void _save() {
    if (_formKey.currentState!.validate()) {
      prefs.setString("username", usernameController.text.trim());
      Navigator.pop(context);
    }
  }
}
