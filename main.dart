import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(const RotaExpressApp());

class RotaExpressApp extends StatelessWidget {
  const RotaExpressApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Rota Express Moto',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1769E0)), useMaterial3: true),
        home: const HomePage(),
      );
}

class Stop {
  Stop({required this.code, required this.address, this.notes = '', this.sequence = 0, this.point});
  final String code;
  final String address;
  final String notes;
  int sequence;
  LatLng? point;
  bool completed = false;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _startController = TextEditingController();
  final _mapController = MapController();
  List<Stop> _stops = [];
  List<LatLng> _routeLine = [];
  LatLng? _startPoint;
  bool _busy = false;
  String _status = 'Importe o PDF do Spoke ou da Shopee para começar.';
  String? _fileName;
  int _completed = 0;

  Future<void> _importPdf() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
    if (result == null || result.files.single.bytes == null) return;
    setState(() { _busy = true; _status = 'Lendo o PDF...'; _fileName = result.files.single.name; });
    try {
      final bytes = result.files.single.bytes!;
      final document = PdfDocument(inputBytes: bytes);
      final buffer = StringBuffer();
      for (var i = 0; i < document.pages.count; i++) {
        buffer.writeln(PdfTextExtractor(document).extractText(startPageIndex: i, endPageIndex: i));
      }
      document.dispose();
      final parsed = _parseStops(buffer.toString());
      if (parsed.isEmpty) throw Exception('Não encontrei paradas no PDF. Verifique se o arquivo contém texto selecionável, não apenas imagens escaneadas.');
      setState(() { _stops = parsed; _routeLine = []; _completed = 0; _status = 'Encontradas ${parsed.length} paradas. Informe o ponto de partida e toque em Otimizar rota.'; });
    } catch (e) {
      setState(() => _status = 'Não foi possível ler esse PDF: $e');
    } finally { setState(() => _busy = false); }
  }

  List<Stop> _parseStops(String raw) {
    // O formato exportado pelo Spoke costuma incluir código BR... e, depois dele,
    // o endereço nas observações. O parser também tenta reconhecer linhas simples.
    final text = raw.replaceAll('\r', '\n').replaceAll(RegExp(r'[\t ]+'), ' ');
    final out = <Stop>[];
    final codePattern = RegExp(r'\b(BR[A-Z0-9]{9,})\b', caseSensitive: false);
    final seen = <String>{};
    for (final match in codePattern.allMatches(text)) {
      final code = match.group(1)!.toUpperCase();
      if (!seen.add(code)) continue;
      final tail = text.substring(match.end, math.min(text.length, match.end + 350).toInt());
      // Exportação Spoke: BR...; endereço; observação.
      var address = '';
      final after = RegExp(r'^\s*[;,:\-]?\s*([^;\n]{4,120})').firstMatch(tail);
      if (after != null) address = after.group(1)!.trim();
      if (_looksLikeAddress(address)) {
        out.add(Stop(code: code, address: _cleanAddress(address), sequence: out.length + 1));
      }
    }
    // Fallback para PDFs/planilhas impressos em que o código aparece em outra coluna.
    if (out.isEmpty) {
      final lines = text.split('\n');
      for (final line in lines) {
        final m = RegExp(r'^\s*(\d{1,3})\s+(.{8,120}?)\s+(BR[A-Z0-9]{9,})\b').firstMatch(line);
        if (m != null) out.add(Stop(code: m.group(3)!, address: _cleanAddress(m.group(2)!), sequence: out.length + 1));
      }
    }
    return out;
  }

  bool _looksLikeAddress(String value) {
    final v = value.toLowerCase();
    return value.length >= 5 && (RegExp(r'\d').hasMatch(value) || v.contains('rua') || v.contains('avenida') || v.contains('r. ') || v.contains('av. '));
  }
  String _cleanAddress(String value) => value.replaceAll(RegExp(r'\s+'), ' ').replaceAll(RegExp(r'^[,;:\s]+|[,;:\s]+$'), '').trim();

  Future<LatLng?> _geocode(String address) async {
    try {
      final locations = await locationFromAddress('$address, São Paulo, Brasil');
      if (locations.isEmpty) return null;
      return LatLng(locations.first.latitude, locations.first.longitude);
    } catch (_) { return null; }
  }

  double _distance(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final la1 = a.latitude * math.pi / 180, la2 = b.latitude * math.pi / 180;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) + math.cos(la1) * math.cos(la2) * math.sin(dLon / 2) * math.sin(dLon / 2);
    return 2 * r * math.asin(math.sqrt(h));
  }

  Future<void> _optimize() async {
    if (_stops.isEmpty) { setState(() => _status = 'Importe um PDF primeiro.'); return; }
    if (_startController.text.trim().isEmpty) { setState(() => _status = 'Digite o endereço de partida.'); return; }
    setState(() { _busy = true; _status = 'Localizando ponto de partida...'; });
    try {
      final origin = await _geocode(_startController.text.trim());
      if (origin == null) throw Exception('Não consegui localizar o ponto de partida. Tente incluir rua, número, bairro e cidade.');
      _startPoint = origin;
      var failed = 0;
      for (var i = 0; i < _stops.length; i++) {
        setState(() => _status = 'Localizando entrega ${i + 1} de ${_stops.length}...');
        _stops[i].point = await _geocode(_stops[i].address);
        if (_stops[i].point == null) failed++;
        // Pausa curta para evitar sobrecarregar o geocodificador do aparelho.
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      final located = _stops.where((s) => s.point != null).toList();
      if (located.isEmpty) throw Exception('Nenhum endereço foi localizado. Confira se o PDF contém endereços completos.');
      // Heurística de vizinho mais próximo por distância geográfica. A linha do mapa
      // depois é obtida pelas ruas via OSRM; para produção, trocar por matriz viária.
      final remaining = [...located];
      final ordered = <Stop>[];
      var cursor = origin;
      while (remaining.isNotEmpty) {
        remaining.sort((a, b) => _distance(cursor, a.point!).compareTo(_distance(cursor, b.point!)));
        final next = remaining.removeAt(0);
        ordered.add(next);
        cursor = next.point!;
      }
      for (var i = 0; i < ordered.length; i++) { ordered[i].sequence = i + 1; }
      _stops = [...ordered, ..._stops.where((s) => s.point == null)];
      await _loadRoadRoute(origin, ordered);
      setState(() => _status = 'Rota criada: ${ordered.length} paradas localizadas${failed > 0 ? '; $failed endereços precisam de revisão' : ''}. A ordem é uma aproximação por proximidade geográfica.');
      if (_routeLine.isNotEmpty) _mapController.move(_routeLine.first, 12.5);
    } catch (e) { setState(() => _status = 'Erro ao montar a rota: $e'); }
    finally { setState(() => _busy = false); }
  }

  Future<void> _loadRoadRoute(LatLng origin, List<Stop> ordered) async {
    _routeLine = [origin, ...ordered.map((s) => s.point!)];
    // OSRM público aceita coordenadas em sequência e devolve o traçado viário.
    // Limita o pedido a 25 pontos por trecho para evitar URLs/limites excessivos.
    final full = <LatLng>[];
    var chunkStart = 0;
    final points = [origin, ...ordered.map((s) => s.point!)];
    while (chunkStart < points.length - 1) {
      final end = math.min(chunkStart + 24, points.length - 1);
      final segment = points.sublist(chunkStart, end + 1);
      final coords = segment.map((p) => '${p.longitude},${p.latitude}').join(';');
      try {
        final uri = Uri.parse('https://router.project-osrm.org/route/v1/driving/$coords?overview=full&geometries=geojson&steps=false');
        final response = await http.get(uri).timeout(const Duration(seconds: 25));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final routes = data['routes'] as List<dynamic>;
          if (routes.isNotEmpty) {
            final geometry = (routes.first as Map<String, dynamic>)['geometry']['coordinates'] as List<dynamic>;
            final decoded = geometry.map((p) => LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble())).toList();
            full.addAll(full.isEmpty ? decoded : decoded.skip(1));
          }
        }
      } catch (_) { /* Usa a linha reta como fallback visual. */ }
      chunkStart = end;
    }
    if (full.isNotEmpty) _routeLine = full;
  }

  Future<void> _openNavigation(Stop stop) async {
    final p = stop.point;
    final destination = p == null ? stop.address : '${p.latitude},${p.longitude}';
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(destination)}&travelmode=driving');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  void dispose() { _startController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final mapped = _stops.where((s) => s.point != null).toList();
    final center = _startPoint ?? (mapped.isNotEmpty ? mapped.first.point! : const LatLng(-23.5505, -46.6333));
    return Scaffold(
      appBar: AppBar(title: const Text('Rota Express Moto'), actions: [IconButton(tooltip: 'Importar PDF', onPressed: _busy ? null : _importPdf, icon: const Icon(Icons.picture_as_pdf))]),
      body: SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FilledButton.icon(onPressed: _busy ? null : _importPdf, icon: const Icon(Icons.upload_file), label: Text(_fileName == null ? 'Importar PDF do Spoke/Shopee' : 'PDF: $_fileName')),
          const SizedBox(height: 10),
          TextField(controller: _startController, decoration: const InputDecoration(labelText: 'Ponto de partida', hintText: 'Rua, número, bairro e cidade', prefixIcon: Icon(Icons.flag), border: OutlineInputBorder())),
          const SizedBox(height: 8),
          FilledButton.icon(onPressed: _busy ? null : _optimize, icon: const Icon(Icons.route), label: const Text('Otimizar rota')),
          if (_busy) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(_status, style: Theme.of(context).textTheme.bodySmall)),
          if (_stops.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('${_stops.length} pedidos • $_completed concluídos', style: const TextStyle(fontWeight: FontWeight.w700))),
        ])),
        if (_routeLine.isNotEmpty || mapped.isNotEmpty) SizedBox(height: 245, child: FlutterMap(mapController: _mapController, options: MapOptions(initialCenter: center, initialZoom: 11), children: [
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.rotaexpress.moto'),
          if (_routeLine.length > 1) PolylineLayer(polylines: [Polyline(points: _routeLine, strokeWidth: 4, color: Colors.blue)]),
          MarkerLayer(markers: [if (_startPoint != null) Marker(point: _startPoint!, width: 38, height: 38, child: const Icon(Icons.flag, color: Colors.green, size: 32)), ...mapped.map((s) => Marker(point: s.point!, width: 34, height: 34, child: Container(decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white, width: 2)), alignment: Alignment.center, child: Text('${s.sequence}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))))]),
        ])),
        Expanded(child: _stops.isEmpty ? const Center(child: Text('Seus pedidos aparecerão aqui após importar o PDF.')) : ListView.separated(itemCount: _stops.length, separatorBuilder: (_, __) => const Divider(height: 1), itemBuilder: (context, index) {
          final s = _stops[index];
          final located = s.point != null;
          return ListTile(leading: CircleAvatar(backgroundColor: s.completed ? Colors.green : (located ? Colors.blue : Colors.orange), foregroundColor: Colors.white, child: Text(s.completed ? '✓' : (located ? '${s.sequence}' : '?'))), title: Text(s.address, style: TextStyle(decoration: s.completed ? TextDecoration.lineThrough : null)), subtitle: Text('${s.code}${located ? '' : ' • revisar endereço'}'), trailing: IconButton(icon: const Icon(Icons.navigation), onPressed: () => _openNavigation(s)), onTap: () => setState(() { if (!s.completed) { s.completed = true; _completed++; } else { s.completed = false; _completed--; } }),);
        })),
      ])),
    );
  }
}
