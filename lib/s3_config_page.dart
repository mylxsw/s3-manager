import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:ploys3/models/s3_server_config.dart';
import 'package:ploys3/core/localization.dart';
import 'package:ploys3/core/design_system.dart';

import 'package:ploys3/widgets/window_title_bar.dart';

class S3ConfigPage extends StatefulWidget {
  final VoidCallback onSave;
  final S3ServerConfig? existingConfig;

  const S3ConfigPage({super.key, required this.onSave, this.existingConfig});

  @override
  State<S3ConfigPage> createState() => _S3ConfigPageState();
}

class _S3ConfigPageState extends State<S3ConfigPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _bucketController = TextEditingController();
  final TextEditingController _accessKeyIdController = TextEditingController();
  final TextEditingController _cdnUrlController = TextEditingController();
  final TextEditingController _secretAccessKeyController = TextEditingController();
  final TextEditingController _regionController = TextEditingController();

  Future<void> _saveConfig() async {
    if (_formKey.currentState!.validate()) {
      final prefs = await SharedPreferences.getInstance();
      final List<String> serverConfigs = prefs.getStringList('server_configs') ?? [];

      if (widget.existingConfig != null) {
        // Editing existing config - preserve the ID
        final updatedConfig = S3ServerConfig(
          id: widget.existingConfig!.id,
          name: _nameController.text,
          address: _addressController.text,
          bucket: _bucketController.text,
          accessKeyId: _accessKeyIdController.text,
          secretAccessKey: _secretAccessKeyController.text,
          region: _regionController.text.isNotEmpty ? _regionController.text : null,
          cdnUrl: _cdnUrlController.text.isNotEmpty ? _cdnUrlController.text : null,
        );

        // Find and replace the existing config
        final index = serverConfigs.indexWhere((configString) {
          final config = S3ServerConfig.fromJson(json.decode(configString));
          return config.id == widget.existingConfig!.id;
        });

        if (index != -1) {
          serverConfigs[index] = json.encode(updatedConfig.toJson());
        }
      } else {
        // Creating new config
        final newConfig = S3ServerConfig(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: _nameController.text,
          address: _addressController.text,
          bucket: _bucketController.text,
          accessKeyId: _accessKeyIdController.text,
          secretAccessKey: _secretAccessKeyController.text,
          region: _regionController.text.isNotEmpty ? _regionController.text : null,
          cdnUrl: _cdnUrlController.text.isNotEmpty ? _cdnUrlController.text : null,
        );

        serverConfigs.add(json.encode(newConfig.toJson()));
      }

      await prefs.setStringList('server_configs', serverConfigs);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.loc('server_saved')), behavior: SnackBarBehavior.floating));
        widget.onSave();
        Navigator.pop(context);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    // If editing existing config, populate the fields
    if (widget.existingConfig != null) {
      _nameController.text = widget.existingConfig!.name;
      _addressController.text = widget.existingConfig!.address;
      _bucketController.text = widget.existingConfig!.bucket;
      _accessKeyIdController.text = widget.existingConfig!.accessKeyId;
      _secretAccessKeyController.text = widget.existingConfig!.secretAccessKey;
      if (widget.existingConfig!.region != null) {
        _regionController.text = widget.existingConfig!.region!;
      }
      if (widget.existingConfig!.cdnUrl != null) {
        _cdnUrlController.text = widget.existingConfig!.cdnUrl!;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _bucketController.dispose();
    _accessKeyIdController.dispose();
    _secretAccessKeyController.dispose();
    _regionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      body: WindowBorder(
        color: Colors.transparent,
        width: 0,
        child: Column(
          children: [
            const WindowTitleBar(),
            Expanded(
              child: Scaffold(
                appBar: AppBar(
                  title: Text(
                    widget.existingConfig != null ? context.loc('title_edit_server') : context.loc('title_add_server'),
                  ),
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  centerTitle: true,
                  actions: [
                    TextButton.icon(
                      onPressed: _saveConfig,
                      label: Text(context.loc('save')),
                      icon: Icon(Icons.save, color: Theme.of(context).colorScheme.primary),
                    ),
                    const SizedBox(width: 12),
                  ],
                ),
                backgroundColor: Colors.transparent,
                body: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: Form(
                        key: _formKey,
                        child: ListView(
                          children: <Widget>[
                            _buildTextFormField(context.loc('name'), _nameController, context.loc('name_hint')),
                            _buildTextFormField(
                              context.loc('address'),
                              _addressController,
                              context.loc('address_hint'),
                            ),
                            _buildTextFormField(context.loc('bucket'), _bucketController, context.loc('bucket_hint')),
                            _buildTextFormField(
                              context.loc('access_key_id'),
                              _accessKeyIdController,
                              context.loc('access_key_hint'),
                            ),
                            _buildTextFormField(
                              context.loc('secret_access_key'),
                              _secretAccessKeyController,
                              context.loc('secret_key_hint'),
                              obscureText: true,
                            ),
                            _buildTextFormField(
                              context.loc('region'),
                              _regionController,
                              context.loc('region_hint'),
                              isOptional: true,
                            ),
                            _buildTextFormField(
                              context.loc('cdn_url'),
                              _cdnUrlController,
                              context.loc('cdn_hint'),
                              isOptional: true,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextFormField(
    String label,
    TextEditingController controller,
    String hintText, {
    bool obscureText = false,
    bool isOptional = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        style: const TextStyle(fontSize: AppFontSizes.md),
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          labelStyle: const TextStyle(fontSize: AppFontSizes.md),
          hintStyle: const TextStyle(fontSize: AppFontSizes.md),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Theme.of(context).indicatorColor, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        validator: (value) {
          // Skip validation for optional fields
          if (isOptional) {
            return null;
          }
          if (value == null || value.isEmpty) {
            return context.loc('validation_required', [label]);
          }
          return null;
        },
      ),
    );
  }
}
