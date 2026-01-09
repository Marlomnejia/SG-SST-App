import 'package:flutter/material.dart';
import '../services/training_service.dart';

class TrainingFormScreen extends StatefulWidget {
  final String? trainingId;
  final Map<String, dynamic>? data;

  const TrainingFormScreen({super.key, this.trainingId, this.data});

  @override
  State<TrainingFormScreen> createState() => _TrainingFormScreenState();
}

class _TrainingFormScreenState extends State<TrainingFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _categoryController = TextEditingController();
  final _durationController = TextEditingController();
  final _contentTextController = TextEditingController();
  final _contentUrlController = TextEditingController();
  final TrainingService _trainingService = TrainingService();

  String _contentType = 'text';
  bool _published = true;
  int _passingScore = 80;
  int _attemptsAllowed = 3;
  bool _mandatory = true;
  String _version = 'v1';
  int _validityMonths = 12;
  final List<Map<String, dynamic>> _quiz = [];

  @override
  void initState() {
    super.initState();
    final data = widget.data;
    if (data != null) {
      _titleController.text = data['title'] ?? '';
      _descriptionController.text = data['description'] ?? '';
      _categoryController.text = data['category'] ?? '';
      _durationController.text = (data['durationMinutes'] ?? 0).toString();
      _contentType = data['contentType'] ?? 'text';
      _contentTextController.text = data['contentText'] ?? '';
      _contentUrlController.text = data['contentUrl'] ?? '';
      _published = data['published'] ?? true;
      _passingScore = data['passingScore'] ?? 80;
      _attemptsAllowed = data['attemptsAllowed'] ?? 3;
      _mandatory = data['mandatory'] ?? true;
      _version = data['version'] ?? 'v1';
      _validityMonths = data['validityMonths'] ?? 12;
      final existingQuiz = data['quiz'] as List?;
      if (existingQuiz != null) {
        _quiz.addAll(existingQuiz.cast<Map<String, dynamic>>());
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _categoryController.dispose();
    _durationController.dispose();
    _contentTextController.dispose();
    _contentUrlController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final data = {
      'title': _titleController.text.trim(),
      'description': _descriptionController.text.trim(),
      'category': _categoryController.text.trim(),
      'durationMinutes': int.tryParse(_durationController.text.trim()) ?? 0,
      'contentType': _contentType,
      'contentText': _contentTextController.text.trim(),
      'contentUrl': _contentUrlController.text.trim(),
      'published': _published,
      'passingScore': _passingScore,
      'attemptsAllowed': _attemptsAllowed,
      'mandatory': _mandatory,
      'version': _version.trim().isEmpty ? 'v1' : _version.trim(),
      'validityMonths': _validityMonths,
      'quiz': _quiz,
    };

    if (widget.trainingId == null) {
      await _trainingService.createTraining(data);
    } else {
      await _trainingService.updateTraining(widget.trainingId!, data);
    }

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  void _addQuizItem() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const _QuizDialog(),
    );
    if (result != null) {
      setState(() {
        _quiz.add(result);
      });
    }
  }

  void _removeQuizItem(int index) {
    setState(() {
      _quiz.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.trainingId == null
            ? 'Nueva capacitacion'
            : 'Editar capacitacion'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _save,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Titulo'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Ingresa un titulo.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Descripcion'),
              maxLines: 3,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Ingresa una descripcion.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _categoryController,
              decoration: const InputDecoration(labelText: 'Categoria de riesgo'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _durationController,
              decoration: const InputDecoration(labelText: 'Duracion (minutos)'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _contentType,
              decoration: const InputDecoration(labelText: 'Tipo de contenido'),
              items: const [
                DropdownMenuItem(value: 'text', child: Text('Lectura')),
                DropdownMenuItem(value: 'video', child: Text('Video (URL)')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _contentType = value;
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            if (_contentType == 'text')
              TextFormField(
                controller: _contentTextController,
                decoration: const InputDecoration(labelText: 'Contenido (texto)'),
                maxLines: 4,
              )
            else
              TextFormField(
                controller: _contentUrlController,
                decoration: const InputDecoration(labelText: 'URL del video'),
              ),
            const SizedBox(height: 16),
            SwitchListTile(
              value: _published,
              onChanged: (value) {
                setState(() {
                  _published = value;
                });
              },
              title: const Text('Publicado'),
            ),
            SwitchListTile(
              value: _mandatory,
              onChanged: (value) {
                setState(() {
                  _mandatory = value;
                });
              },
              title: const Text('Obligatoria'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: _passingScore.toString(),
              decoration: const InputDecoration(labelText: 'Nota minima (%)'),
              keyboardType: TextInputType.number,
              onChanged: (value) {
                _passingScore = int.tryParse(value) ?? _passingScore;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: _attemptsAllowed.toString(),
              decoration: const InputDecoration(labelText: 'Intentos permitidos'),
              keyboardType: TextInputType.number,
              onChanged: (value) {
                _attemptsAllowed = int.tryParse(value) ?? _attemptsAllowed;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: _version,
              decoration: const InputDecoration(labelText: 'Version'),
              onChanged: (value) {
                _version = value;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: _validityMonths.toString(),
              decoration: const InputDecoration(labelText: 'Vigencia (meses)'),
              keyboardType: TextInputType.number,
              onChanged: (value) {
                _validityMonths = int.tryParse(value) ?? _validityMonths;
              },
            ),
            const SizedBox(height: 20),
            Text(
              'Quiz',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ..._quiz.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final question = item['question'] ?? 'Pregunta';
              return Card(
                child: ListTile(
                  title: Text(question),
                  subtitle: Text('Opciones: ${(item['options'] as List).length}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _removeQuizItem(index),
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _addQuizItem,
              icon: const Icon(Icons.add),
              label: const Text('Agregar pregunta'),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _save,
              child: const Text('Guardar capacitacion'),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuizDialog extends StatefulWidget {
  const _QuizDialog();

  @override
  State<_QuizDialog> createState() => _QuizDialogState();
}

class _QuizDialogState extends State<_QuizDialog> {
  final _questionController = TextEditingController();
  final _optionControllers = List.generate(4, (_) => TextEditingController());
  int _correctIndex = 0;

  @override
  void dispose() {
    _questionController.dispose();
    for (final controller in _optionControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nueva pregunta'),
      content: SingleChildScrollView(
        child: Column(
          children: [
            TextField(
              controller: _questionController,
              decoration: const InputDecoration(labelText: 'Pregunta'),
            ),
            const SizedBox(height: 12),
            ...List.generate(_optionControllers.length, (index) {
              return TextField(
                controller: _optionControllers[index],
                decoration: InputDecoration(labelText: 'Opcion ${index + 1}'),
              );
            }),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: _correctIndex,
              decoration: const InputDecoration(labelText: 'Respuesta correcta'),
              items: List.generate(
                _optionControllers.length,
                (index) => DropdownMenuItem(
                  value: index,
                  child: Text('Opcion ${index + 1}'),
                ),
              ),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _correctIndex = value;
                  });
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            final question = _questionController.text.trim();
            final options = _optionControllers
                .map((controller) => controller.text.trim())
                .where((value) => value.isNotEmpty)
                .toList();
            if (question.isEmpty || options.length < 2) {
              return;
            }
            Navigator.pop(context, {
              'question': question,
              'options': options,
              'correctIndex': _correctIndex.clamp(0, options.length - 1),
            });
          },
          child: const Text('Agregar'),
        ),
      ],
    );
  }
}
