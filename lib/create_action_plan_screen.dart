
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class CreateActionPlanScreen extends StatefulWidget {
  final String eventId;

  const CreateActionPlanScreen({super.key, required this.eventId});

  @override
  State<CreateActionPlanScreen> createState() => _CreateActionPlanScreenState();
}

class _CreateActionPlanScreenState extends State<CreateActionPlanScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descripcionController = TextEditingController();
  final _asignadoAController = TextEditingController();
  DateTime? _selectedDate;
  bool _isSaving = false;

  @override
  void dispose() {
    _descripcionController.dispose();
    _asignadoAController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _saveActionPlan() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, selecciona una fecha límite')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await FirebaseFirestore.instance.collection('planesDeAccion').add({
        'descripcion': _descripcionController.text,
        'asignadoA': _asignadoAController.text,
        'fechaLimite': Timestamp.fromDate(_selectedDate!),
        'estado': 'pendiente',
        'eventoId': widget.eventId,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Plan de acción guardado correctamente')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar el plan de acción: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nuevo Plan de Acción'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _descripcionController,
                decoration: const InputDecoration(
                  labelText: 'Descripción de la Tarea',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Por favor, ingresa una descripción';
                  }
                  return null;
                },
                maxLines: 3,
              ),
              const SizedBox(height: 16.0),
              TextFormField(
                controller: _asignadoAController,
                decoration: const InputDecoration(
                  labelText: 'Asignado A',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Por favor, asigna la tarea a alguien';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16.0),
              ListTile(
                title: const Text('Fecha Límite'),
                subtitle: Text(
                  _selectedDate == null
                      ? 'No seleccionada'
                      : DateFormat('dd/MM/yyyy').format(_selectedDate!),
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: () => _selectDate(context),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4.0),
                  side: const BorderSide(color: Colors.grey),
                ),
              ),
              const SizedBox(height: 24.0),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveActionPlan,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(color: Colors.white),
                        )
                      : const Text('Guardar Plan'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
