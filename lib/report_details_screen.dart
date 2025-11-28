import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'full_screen_image_screen.dart';

class ReportDetailsScreen extends StatefulWidget {
  final String documentId;

  const ReportDetailsScreen({Key? key, required this.documentId}) : super(key: key);

  @override
  _ReportDetailsScreenState createState() => _ReportDetailsScreenState();
}

class _ReportDetailsScreenState extends State<ReportDetailsScreen> {
  late Future<DocumentSnapshot> _reportFuture;

  @override
  void initState() {
    super.initState();
    _reportFuture = FirebaseFirestore.instance.collection('eventos').doc(widget.documentId).get();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalles del Reporte'),
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: _reportFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('Error al cargar los detalles.'));
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('No se encontró el reporte.'));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: ListView(
              children: [
                _buildDetailItem('Tipo', data['tipo']),
                _buildDetailItem('Descripción', data['descripcion']),
                _buildDetailItem('Fecha del Reporte', (data['fechaReporte'] as Timestamp).toDate().toString()),
                _buildDetailItem('Estado', data['estado']),
                if (data.containsKey('fotoUrls') && (data['fotoUrls'] as List).isNotEmpty)
                  _buildImageGrid(data['fotoUrls'] as List<dynamic>),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDetailItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildImageGrid(List<dynamic> imageUrls) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Imágenes',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            itemCount: imageUrls.length,
            itemBuilder: (context, index) {
              final imageUrl = imageUrls[index];
              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => FullScreenImageScreen(imageUrl: imageUrl),
                    ),
                  );
                },
                child: Image.network(imageUrl, fit: BoxFit.cover),
              );
            },
          ),
        ],
      ),
    );
  }
}