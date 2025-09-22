import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:charts_flutter/flutter.dart' as charts;

void main() {
  runApp(const InventoryApp());
}

// -------------------- APP --------------------
class InventoryApp extends StatelessWidget {
  const InventoryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Inventario Offline',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const InventoryScreen(),
    );
  }
}

// -------------------- DATABASE HELPER --------------------
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();
  factory DatabaseHelper() => instance;
  DatabaseHelper._internal();

  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    return openDatabase(
      p.join(dbPath, 'inventario.db'),
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE materiales(
        id TEXT PRIMARY KEY,
        nombre TEXT,
        stock INTEGER,
        precio REAL,
        ventas INTEGER,
        created_at TEXT
      )
    ''');
  }

  Future<List<Map<String, dynamic>>> getMateriales() async {
    final db = await database;
    return db.query('materiales', orderBy: 'created_at DESC');
  }

  Future<void> insertMaterial(Map<String, dynamic> data) async {
    final db = await database;
    await db.insert('materiales', data, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteMaterial(String id) async {
    final db = await database;
    await db.delete('materiales', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateMaterial(String id, Map<String, dynamic> data) async {
    final db = await database;
    await db.update('materiales', data, where: 'id = ?', whereArgs: [id]);
  }
}

// -------------------- INVENTORY SCREEN --------------------
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final dbHelper = DatabaseHelper.instance;
  List<Map<String, dynamic>> materiales = [];
  bool loading = true;

  final TextEditingController _nombreController = TextEditingController();
  final TextEditingController _stockController = TextEditingController();
  final TextEditingController _precioController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadLocal();
  }

  Future<void> _loadLocal() async {
    final data = await dbHelper.getMateriales();
    setState(() {
      materiales = data;
      loading = false;
    });
  }

  Future<void> _deleteMaterial(String id) async {
    await dbHelper.deleteMaterial(id);
    await _loadLocal();
  }

  Future<void> _addMaterial() async {
    if (_nombreController.text.isEmpty) return;

    final id = const Uuid().v4();
    final now = DateTime.now().toIso8601String();

    await dbHelper.insertMaterial({
      'id': id,
      'nombre': _nombreController.text,
      'stock': int.tryParse(_stockController.text) ?? 0,
      'precio': double.tryParse(_precioController.text) ?? 0.0,
      'ventas': 0,
      'created_at': now,
    });

    _nombreController.clear();
    _stockController.clear();
    _precioController.clear();
    await _loadLocal();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _editMaterial(Map<String, dynamic> mat) async {
    _nombreController.text = mat['nombre'];
    _stockController.text = mat['stock'].toString();
    _precioController.text = mat['precio'].toString();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar Material'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _nombreController, decoration: const InputDecoration(labelText: 'Nombre')),
            TextField(controller: _stockController, decoration: const InputDecoration(labelText: 'Stock'), keyboardType: TextInputType.number),
            TextField(controller: _precioController, decoration: const InputDecoration(labelText: 'Precio'), keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              await dbHelper.updateMaterial(mat['id'], {
                'nombre': _nombreController.text,
                'stock': int.tryParse(_stockController.text) ?? 0,
                'precio': double.tryParse(_precioController.text) ?? 0.0,
              });
              _nombreController.clear();
              _stockController.clear();
              _precioController.clear();
              await _loadLocal();
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _venderMaterial(Map<String, dynamic> mat) async {
    final TextEditingController vendidoController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Vender ${mat['nombre']}'),
        content: TextField(controller: vendidoController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cantidad Vendida')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              final vendido = int.tryParse(vendidoController.text) ?? 0;
              if (vendido > 0 && vendido <= mat['stock']) {
                final nuevoStock = mat['stock'] - vendido;
                final totalVentas = mat['ventas'] + vendido;
                await dbHelper.updateMaterial(mat['id'], {
                  'nombre': mat['nombre'],
                  'stock': nuevoStock,
                  'precio': mat['precio'],
                  'ventas': totalVentas,
                });
                await _loadLocal();
              }
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  void _showAddDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Añadir Material'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _nombreController, decoration: const InputDecoration(labelText: 'Nombre')),
            TextField(controller: _stockController, decoration: const InputDecoration(labelText: 'Stock'), keyboardType: TextInputType.number),
            TextField(controller: _precioController, decoration: const InputDecoration(labelText: 'Precio'), keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(onPressed: _addMaterial, child: const Text('Guardar')),
        ],
      ),
    );
  }

  void _showHistorial(String nombre) {
    final filtrado = materiales.where((m) => m['nombre'] == nombre).toList();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Historial de $nombre'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            children: filtrado
                .map((m) => ListTile(
                      title: Text(m['nombre']),
                      subtitle: Text("Stock: ${m['stock']}  Vendidos: ${m['ventas']}  Precio: \$${m['precio']}"),
                    ))
                .toList(),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(title: const Text("Inventario Offline")),
      floatingActionButton: FloatingActionButton(onPressed: _showAddDialog, child: const Icon(Icons.add)),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                ...materiales.map((mat) => inventarioItem(mat)).toList(),
                const SizedBox(height: 20),
                graficoBarrasCharts(
                  "📊 Productos Más Vendidos",
                  {for (var m in materiales) m['nombre']: m['ventas'].toDouble()},
                ),
                graficoBarrasCharts(
                  "💰 Ingresos por Producto",
                  {for (var m in materiales) m['nombre']: (m['precio'] * m['ventas'])},
                ),
              ],
            ),
    );
  }

  Widget inventarioItem(Map<String, dynamic> mat) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [
        BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))
      ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(mat['nombre'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              Row(children: [
                actionBtn(Icons.edit, Colors.blue, () => _editMaterial(mat)),
                const SizedBox(width: 8),
                mat['stock'] > 0
                    ? actionBtn(Icons.shopping_cart, Colors.green, () => _venderMaterial(mat))
                    : const Icon(Icons.warning, color: Colors.orange),
                const SizedBox(width: 8),
                actionBtn(Icons.delete, Colors.red, () => _deleteMaterial(mat['id'])),
              ])
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
decoration: BoxDecoration(
                  color: mat['stock'] == 0
                      ? Colors.red
                      : mat['stock'] < 5
                          ? Colors.orange
                          : Colors.green,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  "Stock: ${mat['stock']}",
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 20),
              Text(
                "Precio: \$${mat['precio']}",
                style:
                    const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500),
              ),
              const SizedBox(width: 20),
              Text(
                "Vendidos: ${mat['ventas']}",
                style: const TextStyle(
                    color: Colors.purple, fontWeight: FontWeight.w500),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget actionBtn(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
          width: 36,
          height: 36,
          decoration:
              BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: Colors.white, size: 20)),
    );
  }

  Widget graficoBarrasCharts(String titulo, Map<String, double> data) {
    final series = [
      charts.Series<MapEntry<String, double>, String>(
        id: titulo,
        domainFn: (entry, _) => entry.key,
        measureFn: (entry, _) => entry.value,
        colorFn: (entry, index) {
          final colors = charts.MaterialPalette.getOrderedPalettes(data.length);
          return colors[index!].shadeDefault;
        },
        data: data.entries.toList(),
        labelAccessorFn: (entry, _) => entry.value.toStringAsFixed(0),
      )
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 15),
          SizedBox(
            height: 200,
            child: charts.BarChart(
              series,
              animate: true,
              vertical: true,
              barRendererDecorator: charts.BarLabelDecorator<String>(),
              domainAxis: const charts.OrdinalAxisSpec(
                  renderSpec: charts.SmallTickRendererSpec(labelRotation: 60)),
            ),
          ),
        ],
      ),
    );
  }
}