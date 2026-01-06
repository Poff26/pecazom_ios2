import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/fishing_pin.dart';
import '../services/pin_services.dart';

Color colorFromHex(String hex) {
  hex = hex.replaceAll('#', '');
  if (hex.length == 6) hex = 'FF$hex';
  return Color(int.parse('0x$hex'));
}

class PinDialog extends StatefulWidget {
  final LatLng position;
  final VoidCallback onSaved;
  final FishingPin? existingPin;

  const PinDialog({
    Key? key,
    required this.position,
    required this.onSaved,
    this.existingPin,
  }) : super(key: key);

  @override
  State<PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<PinDialog> {
  final _formKey = GlobalKey<FormState>();

  late String _name;
  late double _fishWeight;
  late String _fishSpecies;
  late double _fishSize;
  late String _pinColor;
  String? _bait;

  File? _newImageFile;

  final ImagePicker _picker = ImagePicker();
  final List<String> _availableColors = ['#FF0000', '#00FF00', '#0000FF', '#FFFF00', '#FF00FF'];

  bool get _isEdit => widget.existingPin != null;

  @override
  void initState() {
    super.initState();
    final p = widget.existingPin;
    _name = p?.name ?? '';
    _fishWeight = p?.fishWeight ?? 0.0;
    _fishSpecies = p?.fishSpecies ?? '';
    _fishSize = p?.fishSize ?? 0.0;
    _pinColor = p?.pinColor ?? '#00FF00';
    _bait = p?.bait;
  }

  Future<void> _takePhoto() async {
    final picked = await _picker.pickImage(source: ImageSource.camera);
    if (picked != null) {
      setState(() => _newImageFile = File(picked.path));
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    _formKey.currentState!.save();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final id = _isEdit
        ? widget.existingPin!.id
        : FirebaseFirestore.instance.collection('fishing_pins').doc().id;

    final pin = FishingPin(
      id: id,
      lat: widget.position.latitude,
      lon: widget.position.longitude,
      name: _name.trim().isEmpty ? 'Ismeretlen hely' : _name.trim(),
      fishWeight: _fishWeight,
      fishSpecies: _fishSpecies.trim(),
      fishSize: _fishSize,
      pinColor: _pinColor.isNotEmpty ? _pinColor : '#00FF00',
      imageUrl: _isEdit ? widget.existingPin!.imageUrl : null,
      userId: user.uid,
      bait: (_bait ?? '').trim().isEmpty ? null : _bait!.trim(),
    );

    if (_isEdit) {
      await PinService().updatePin(pin, newImage: _newImageFile);
    } else {
      await PinService().addPin(pin, _newImageFile);
    }

    widget.onSaved();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Hely szerkesztése' : 'Új hely hozzáadása'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Koordináták: ${widget.position.latitude.toStringAsFixed(4)}, ${widget.position.longitude.toStringAsFixed(4)}',
              ),
              TextFormField(
                initialValue: _name,
                decoration: const InputDecoration(labelText: 'Hely neve'),
                onSaved: (v) => _name = v ?? '',
              ),
              TextFormField(
                initialValue: _fishWeight == 0 ? '' : _fishWeight.toString(),
                decoration: const InputDecoration(labelText: 'Hal súlya (kg)'),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.isEmpty) return null;
                  return double.tryParse(v) == null ? 'Érvényes számot adj meg' : null;
                },
                onSaved: (v) => _fishWeight = double.tryParse(v ?? '') ?? 0,
              ),
              TextFormField(
                initialValue: _fishSpecies,
                decoration: const InputDecoration(labelText: 'Hal faja'),
                onSaved: (v) => _fishSpecies = v ?? '',
              ),
              TextFormField(
                initialValue: _fishSize == 0 ? '' : _fishSize.toString(),
                decoration: const InputDecoration(labelText: 'Hal mérete (cm)'),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.isEmpty) return null;
                  return double.tryParse(v) == null ? 'Érvényes számot adj meg' : null;
                },
                onSaved: (v) => _fishSize = double.tryParse(v ?? '') ?? 0,
              ),
              TextFormField(
                initialValue: _bait ?? '',
                decoration: const InputDecoration(labelText: 'Csali (opcionális)'),
                onSaved: (v) => _bait = v,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  ElevatedButton(
                    onPressed: _takePhoto,
                    child: Text(_isEdit ? 'Kép cseréje' : 'Készíts fotót'),
                  ),
                  const SizedBox(width: 8),
                  if (_newImageFile != null)
                    SizedBox(width: 50, height: 50, child: Image.file(_newImageFile!)),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: _availableColors.map((hex) {
                  final color = colorFromHex(hex);
                  final selected = _pinColor == hex;
                  return GestureDetector(
                    onTap: () => setState(() => _pinColor = hex),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: selected ? Border.all(width: 3) : null,
                      ),
                      child: CircleAvatar(backgroundColor: color, radius: 16),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              Text('Választott szín: $_pinColor'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Mégsem')),
        ElevatedButton(onPressed: _save, child: Text(_isEdit ? 'Frissítés' : 'Mentés')),
      ],
    );
  }
}
