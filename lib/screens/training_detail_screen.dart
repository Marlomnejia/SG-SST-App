import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/training_service.dart';

class TrainingDetailScreen extends StatefulWidget {
  final String trainingId;
  final Map<String, dynamic> data;

  const TrainingDetailScreen({
    super.key,
    required this.trainingId,
    required this.data,
  });

  @override
  State<TrainingDetailScreen> createState() => _TrainingDetailScreenState();
}

class _TrainingDetailScreenState extends State<TrainingDetailScreen> {
  final TrainingService _trainingService = TrainingService();
  final Map<int, int> _answers = {};
  bool _isSubmitting = false;
  bool _acceptedStatement = false;
  int? _attemptsUsed;

  @override
  void initState() {
    super.initState();
    _loadAttempts();
  }

  Future<void> _loadAttempts() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }
    final attempts =
        await _trainingService.countAttempts(widget.trainingId, user.uid);
    if (mounted) {
      setState(() {
        _attemptsUsed = attempts;
      });
    }
  }

  Future<void> _submitQuiz() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    final List<dynamic> quiz = widget.data['quiz'] ?? [];
    if (quiz.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay quiz configurado.')),
      );
      return;
    }

    if (!_acceptedStatement) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes aceptar la declaracion final.')),
      );
      return;
    }

    if (_answers.length != quiz.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Responde todas las preguntas.')),
      );
      return;
    }

    final int total = quiz.length;
    int correct = 0;
    for (int i = 0; i < quiz.length; i++) {
      final Map<String, dynamic> item = quiz[i] as Map<String, dynamic>;
      final int correctIndex = item['correctIndex'] ?? 0;
      if (_answers[i] == correctIndex) {
        correct++;
      }
    }

    final int score = ((correct / total) * 100).round();
    final int passingScore = widget.data['passingScore'] ?? 80;
    final bool passed = score >= passingScore;

    setState(() {
      _isSubmitting = true;
    });

    try {
      await _trainingService.saveAttempt(
        trainingId: widget.trainingId,
        uid: user.uid,
        score: score,
        passed: passed,
        totalQuestions: total,
        trainingVersion: widget.data['version'],
      );
      if (passed) {
        await _trainingService.issueCertificate(
          trainingId: widget.trainingId,
          uid: user.uid,
          score: score,
          trainingVersion: widget.data['version'],
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              passed
                  ? 'Aprobado. Se genero el certificado.'
                  : 'No aprobaste. Intenta de nuevo.',
            ),
          ),
        );
        await _loadAttempts();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final String title = widget.data['title'] ?? 'Capacitacion';
    final String description = widget.data['description'] ?? '';
    final String category = widget.data['category'] ?? 'General';
    final int duration = widget.data['durationMinutes'] ?? 0;
    final int passingScore = widget.data['passingScore'] ?? 80;
    final int attemptsAllowed = widget.data['attemptsAllowed'] ?? 3;
    final int validityMonths = widget.data['validityMonths'] ?? 12;
    final String contentType = widget.data['contentType'] ?? 'text';
    final String contentUrl = widget.data['contentUrl'] ?? '';
    final String contentText = widget.data['contentText'] ?? '';
    final List<dynamic> quiz = widget.data['quiz'] ?? [];

    final int attemptsUsed = _attemptsUsed ?? 0;
    final int attemptsLeft = attemptsAllowed - attemptsUsed;
    final bool canAttempt = attemptsLeft > 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _InfoRow(label: 'Categoria', value: category),
          _InfoRow(label: 'Duracion', value: '$duration min'),
          _InfoRow(label: 'Nota minima', value: '$passingScore%'),
          _InfoRow(label: 'Intentos restantes', value: '$attemptsLeft'),
          _InfoRow(label: 'Vigencia', value: '$validityMonths meses'),
          const SizedBox(height: 16),
          Text(
            'Objetivo',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(description),
          const SizedBox(height: 16),
          Text(
            'Contenido',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (contentType == 'video')
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Text(
                contentUrl.isNotEmpty
                    ? contentUrl
                    : 'No hay URL configurada.',
              ),
            )
          else
            Text(contentText.isNotEmpty ? contentText : 'Contenido no disponible.'),
          const SizedBox(height: 24),
          Text(
            'Quiz',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (quiz.isEmpty)
            const Text('No hay preguntas configuradas.')
          else
            Column(
              children: List.generate(quiz.length, (index) {
                final item = quiz[index] as Map<String, dynamic>;
                final question = item['question'] ?? 'Pregunta';
                final options = (item['options'] as List?) ?? [];

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${index + 1}. $question',
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        ...List.generate(options.length, (optIndex) {
                          final option = options[optIndex].toString();
                          return RadioListTile<int>(
                            value: optIndex,
                            groupValue: _answers[index],
                            title: Text(option),
                            onChanged: canAttempt
                                ? (value) {
                                    setState(() {
                                      _answers[index] = value ?? 0;
                                    });
                                  }
                                : null,
                          );
                        }),
                      ],
                    ),
                  ),
                );
              }),
            ),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: _acceptedStatement,
            onChanged: canAttempt
                ? (value) {
                    setState(() {
                      _acceptedStatement = value ?? false;
                    });
                  }
                : null,
            title: const Text('Declaro haber recibido y comprendido el contenido.'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (!canAttempt || _isSubmitting) ? null : _submitQuiz,
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(),
                    )
                  : Text(canAttempt
                      ? 'Enviar quiz'
                      : 'No tienes intentos disponibles'),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(value),
          ),
        ],
      ),
    );
  }
}
