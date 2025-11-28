
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'full_screen_image_screen.dart';
import 'create_action_plan_screen.dart'; // Import the new screen

class IncidentDetailScreen extends StatefulWidget {
  final QueryDocumentSnapshot eventDocument;

  const IncidentDetailScreen({super.key, required this.eventDocument});

  @override
  State<IncidentDetailScreen> createState() => _IncidentDetailScreenState();
}

class _IncidentDetailScreenState extends State<IncidentDetailScreen> {
  String? _selectedStatus;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedStatus = widget.eventDocument['estado'];
  }

  Future<void> _updateStatus() async {
    if (_selectedStatus == null || _selectedStatus == widget.eventDocument['estado']) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await widget.eventDocument.reference.update({'estado': _selectedStatus});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Estado actualizado correctamente')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al actualizar el estado: $e')),
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

  void _showUpdatePlanStatusDialog(DocumentSnapshot planDoc) {
    final planData = planDoc.data() as Map<String, dynamic>;
    String currentStatus = planData['estado'] ?? 'pendiente';

    showDialog(
      context: context,
      builder: (BuildContext context) {
        String? newStatus = currentStatus;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text("Actualizar Estado del Plan"),
              content: DropdownButtonFormField<String>(
                value: newStatus,
                items: ['pendiente', 'realizado']
                    .map((label) => DropdownMenuItem(
                          value: label,
                          child: Text(label),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      newStatus = value;
                    });
                  }
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancelar"),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (newStatus != null && newStatus != currentStatus) {
                      planDoc.reference.update({'estado': newStatus});
                    }
                    Navigator.pop(context);
                  },
                  child: const Text("Actualizar"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.eventDocument.data() as Map<String, dynamic>;

    final String tipo = data['tipo'] ?? 'No especificado';
    final String descripcion = data['descripcion'] ?? 'Sin descripción';
    final String reportadoPor = data['reportadoPor_email'] ?? 'Anónimo';
    final Timestamp timestamp = data['fechaReporte'] ?? Timestamp.now();
    final List<dynamic> fotoUrls = data['fotoUrls'] ?? [];

    final DateTime fechaReporte = timestamp.toDate();
    final String fechaFormateada = DateFormat('dd/MM/yyyy, hh:mm a').format(fechaReporte);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle del Reporte'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Chip(
              label: Text(
                tipo.toUpperCase(),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              backgroundColor: tipo == 'Accidente' ? Colors.red : Colors.orange,
            ),
            const SizedBox(height: 16.0),
            Text(
              descripcion,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16.0),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('Reportado por'),
              subtitle: Text(reportadoPor),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: const Text('Fecha del Reporte'),
              subtitle: Text(fechaFormateada),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Estado Actual'),
              subtitle: Text(widget.eventDocument['estado'] ?? 'desconocido'),
            ),
            const Divider(),
            const SizedBox(height: 16.0),
            if (fotoUrls.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Fotos Adjuntas:',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8.0),
                  SizedBox(
                    height: 200,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: fotoUrls.length,
                      itemBuilder: (context, index) {
                        final url = fotoUrls[index] as String;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => FullScreenImageScreen(imageUrl: url),
                                ),
                              );
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8.0),
                              child: Image.network(
                                url,
                                fit: BoxFit.cover,
                                width: 150,
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                },
                                errorBuilder: (context, error, stackTrace) {
                                  return const Icon(Icons.error);
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24.0),
                ],
              ),
            DropdownButtonFormField<String>(
              value: _selectedStatus,
              decoration: const InputDecoration(
                labelText: 'Actualizar Estado',
                border: OutlineInputBorder(),
              ),
              items: ['reportado', 'en revisión', 'solucionado']
                  .map((label) => DropdownMenuItem(
                        value: label,
                        child: Text(label),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedStatus = value;
                  });
                }
              },
            ),
            const SizedBox(height: 24.0),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _updateStatus,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                ),
                child: _isSaving
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : const Text('Guardar Cambios'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          CreateActionPlanScreen(eventId: widget.eventDocument.id),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                ),
                child: const Text('Crear Plan de Acción'),
              ),
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 10),
            Text(
              'Planes de Acción Asociados:',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('planesDeAccion')
                  .where('eventoId', isEqualTo: widget.eventDocument.id)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text('No hay planes de acción para este evento.'),
                  );
                }

                final planDocs = snapshot.data!.docs;

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: planDocs.length,
                  itemBuilder: (context, index) {
                    final planDoc = planDocs[index];
                    final planData = planDoc.data() as Map<String, dynamic>;
                    final String estado = planData['estado'] ?? 'desconocido';

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8.0),
                      child: ListTile(
                        title: Text(planData['descripcion'] ?? 'Sin descripción'),
                        subtitle: Text(
                          'Asignado a: ${planData['asignadoA'] ?? 'N/A'}\n'
                          'Límite: ${planData.containsKey('fechaLimite') && planData['fechaLimite'] != null ? DateFormat('dd/MM/yyyy').format((planData['fechaLimite'] as Timestamp).toDate()) : 'No especificada'}',
                        ),
                        trailing: Chip(
                          label: Text(
                            estado,
                            style: const TextStyle(color: Colors.white),
                          ),
                          backgroundColor: estado == 'realizado' ? Colors.green : Colors.orange,
                        ),
                        onTap: () => _showUpdatePlanStatusDialog(planDoc),
                      ),
                    );
                  },
                );
              },
            ),

          ],
        ),
      ),
    );
  }
}
