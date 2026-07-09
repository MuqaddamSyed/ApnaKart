import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/map_config.dart';
import '../../../shared/models/delivery_agent.dart';
import '../../../shared/services/supabase_client.dart';

/// Agent list + live map of all online agents' locations.
class AdminAgentsScreen extends StatefulWidget {
  const AdminAgentsScreen({super.key});
  @override
  State<AdminAgentsScreen> createState() => _State();
}

class _State extends State<AdminAgentsScreen> {
  List<DeliveryAgent> _agents = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    // Stable order by id so a verify toggle doesn't reshuffle the list
    // (Postgres returns unordered rows in a different order after an update).
    final rows =
        await supabase.from('delivery_agents').select().order('id');
    _agents = (rows as List).map((e) => DeliveryAgent.fromMap(e)).toList();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _setVerified(DeliveryAgent agent, bool verified) async {
    try {
      await supabase
          .from('delivery_agents')
          .update({'is_verified': verified})
          .eq('id', agent.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not update: $e')));
      }
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    // Only pin agents that are actually online (available) with a location,
    // matching the "Online/Offline" label shown in the list.
    final online = _agents
        .where((a) =>
            a.isVerified &&
            a.isAvailable &&
            a.currentLat != null &&
            a.currentLng != null)
        .toList();
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Delivery Agents', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Expanded(
          child: Row(children: [
            Expanded(
              flex: 2,
              child: ListView(
                children: _agents.map((a) => Card(
                      child: ListTile(
                        leading: Icon(Icons.delivery_dining,
                            color: a.isVerified
                                ? (a.isAvailable ? AppColors.secondary : AppColors.textMuted)
                                : AppColors.warning),
                        title: Text(a.name?.isNotEmpty == true
                            ? a.name!
                            : 'Agent ${a.id.substring(0, 8)}'),
                        subtitle: Text('${a.vehicleType ?? '-'}  •  ${a.totalDeliveries} deliveries'),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(
                            a.isVerified
                                ? (a.isAvailable ? 'Online' : 'Offline')
                                : 'Pending',
                            style: TextStyle(
                              color: a.isVerified
                                  ? (a.isAvailable ? AppColors.secondary : AppColors.textMuted)
                                  : AppColors.warning,
                              fontSize: 12,
                            ),
                          ),
                          Switch(
                            value: a.isVerified,
                            activeColor: AppColors.secondary,
                            onChanged: (v) => _setVerified(a, v),
                          ),
                        ]),
                      ),
                    )).toList(),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: FlutterMap(
                  options: const MapOptions(
                      initialCenter: LatLng(14.4644, 75.9218), initialZoom: 12),
                  children: [
                    TileLayer(
                      urlTemplate: MapConfig.tileUrl,
                      userAgentPackageName: 'com.quickkart.admin',
                    ),
                    MarkerLayer(
                      markers: online
                          .map((a) => Marker(
                                point: LatLng(a.currentLat!, a.currentLng!),
                                child: const Icon(Icons.location_on,
                                    color: AppColors.primary, size: 32),
                              ))
                          .toList(),
                    ),
                    const SimpleAttributionWidget(
                      source: Text(MapConfig.attribution),
                      backgroundColor: Colors.white70,
                    ),
                  ],
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
