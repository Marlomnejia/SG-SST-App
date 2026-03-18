import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapPreviewScreen extends StatelessWidget {
  final double latitude;
  final double longitude;
  final String? address;

  const MapPreviewScreen({
    super.key,
    required this.latitude,
    required this.longitude,
    this.address,
  });

  @override
  Widget build(BuildContext context) {
    final center = LatLng(latitude, longitude);
    return Scaffold(
      appBar: AppBar(title: const Text('Ubicacion')),
      body: Column(
        children: [
          Expanded(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(target: center, zoom: 16),
              markers: {
                Marker(
                  markerId: const MarkerId('event_location'),
                  position: center,
                ),
              },
              zoomControlsEnabled: true,
              myLocationEnabled: false,
              myLocationButtonEnabled: false,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (address != null && address!.trim().isNotEmpty)
                  Text(
                    address!.trim(),
                    style: Theme.of(context).textTheme.bodyMedium,
                  )
                else
                  Text(
                    'Lat: ${latitude.toStringAsFixed(5)}, Lng: ${longitude.toStringAsFixed(5)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                const SizedBox(height: 6),
                Text(
                  'Mapa Google',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
