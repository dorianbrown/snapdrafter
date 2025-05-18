import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserSettings extends StatefulWidget {
  const UserSettings({Key? key}) : super(key: key);

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

  initPreferences() async {
    prefs = await SharedPreferences.getInstance();
    usernameController.text = prefs.getString("username") ?? "";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('User Settings')),
      body: Form(
        key: _formKey,
        child: Container(
          padding: EdgeInsets.all(50),
          child: Column(
              children: [
                TextFormField(
                  controller: usernameController,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter some text';
                    }
                    return null;
                  },
                  decoration: InputDecoration(
                      hintText: "Username",
                      hintStyle: TextStyle(color: Colors.white54)
                  ),
                )
              ]
          ),
        )
      ),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => {
            if (_formKey.currentState!.validate()) {
              prefs.setString("username", usernameController.text),
              Navigator.pop(context)
            }
          },
          label: Text("Save"),
          icon: Icon(Icons.save),
      )
    );
  }
}
