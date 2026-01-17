import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';
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
    _reportFuture =
        FirebaseFirestore.instance.collection('eventos').doc(widget.documentId).get();
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) {
      return 'No disponible';
    }
    return DateFormat('dd/MM/yyyy, hh:mm a').format(timestamp.toDate());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalles del reporte'),
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
            return const Center(child: Text('No se encontro el reporte.'));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final Timestamp? fechaEvento = data['fechaEvento'] as Timestamp?;
          final GeoPoint? ubicacionGps = data['ubicacionGps'] as GeoPoint?;
          final String? direccionGps = data['direccionGps'] as String?;
          final List<dynamic> videoUrls = data['videoUrls'] ?? [];

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: ListView(
              children: [
                _buildDetailItem('Tipo', data['tipo'] ?? 'No especificado'),
                _buildDetailItem('Categoria', data['categoria'] ?? 'No especificada'),
                _buildDetailItem('Severidad', data['severidad'] ?? 'No especificada'),
                _buildDetailItem('Lugar / area', data['lugar'] ?? 'No especificado'),
                _buildDetailItem(
                    'Fecha del reporte', _formatTimestamp(data['fechaReporte'])),
                if (fechaEvento != null)
                  _buildDetailItem('Fecha del evento', _formatTimestamp(fechaEvento)),
                if (ubicacionGps != null ||
                    (direccionGps != null && direccionGps.isNotEmpty))
                  _buildDetailItem(
                    'Ubicacion GPS',
                    (direccionGps != null && direccionGps.isNotEmpty)
                        ? direccionGps
                        : 'Lat: ${ubicacionGps!.latitude.toStringAsFixed(5)}, Lng: ${ubicacionGps.longitude.toStringAsFixed(5)}',
                  ),
                _buildDetailItem('Estado', data['estado'] ?? 'Desconocido'),
                _buildDetailItem(
                    'Descripcion', data['descripcion'] ?? 'Sin descripcion'),
                if (data.containsKey('fotoUrls') && (data['fotoUrls'] as List).isNotEmpty)
                  _buildImageGrid(data['fotoUrls'] as List<dynamic>),
                if (videoUrls.isNotEmpty) _buildVideoList(videoUrls),
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
            'Imagenes',
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
                      builder: (context) =>
                          FullScreenImageScreen(imageUrl: imageUrl),
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

  Widget _buildVideoList(List<dynamic> videoUrls) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Videos',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 220,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: videoUrls.length,
              itemBuilder: (context, index) {
                final url = videoUrls[index] as String;
                return Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: _NetworkVideoCard(url: url),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NetworkVideoCard extends StatefulWidget {
  final String url;

  const _NetworkVideoCard({required this.url});

  @override
  State<_NetworkVideoCard> createState() => _NetworkVideoCardState();
}

class _NetworkVideoCardState extends State<_NetworkVideoCard> {
  late final VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller.setLooping(true);
    _controller.setVolume(0);
    _controller.initialize().then((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          alignment: Alignment.center,
          children: [
            AspectRatio(
              aspectRatio:
                  _controller.value.isInitialized ? _controller.value.aspectRatio : 16 / 9,
              child: _controller.value.isInitialized
                  ? VideoPlayer(_controller)
                  : Container(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                    ),
            ),
            IconButton(
              icon: Icon(
                _controller.value.isPlaying
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_fill,
                size: 52,
                color: Colors.white,
              ),
              onPressed: () {
                setState(() {
                  if (_controller.value.isPlaying) {
                    _controller.pause();
                  } else {
                    _controller.play();
                  }
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}
