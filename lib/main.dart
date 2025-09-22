import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

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
      home: const SetupScreen(),
    );
  }
}

// -------------------- SETUP SCREEN --------------------
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final TextEditingController _usuarioController = TextEditingController();
  String codigo = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    _usuarioController.text = prefs.getString('usuario') ?? '';
    codigo = prefs.getString('codigo') ?? const Uuid().v4();
    await prefs.setString('codigo', codigo);
    setState(() {});
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('usuario', _usuarioController.text);
    await prefs.setString('codigo', codigo);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(40),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [BoxShadow(blurRadius: 10, color: Colors.black12)],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'INVENTARIO',
                style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w300,
                    color: Colors.blue),
              ),
              const SizedBox(height: 50),
              TextField(
                controller: _usuarioController,
                decoration: const InputDecoration(
                  labelText: 'Nombre',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(25))),
                ),
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () async {
                  await _saveData();
                  if (!mounted) return;
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => InventoryScreen(
                          usuario: _usuarioController.text, codigo: codigo),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25)),
                ),
                child: const Text('ENTRAR', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
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
        inventario_id TEXT,
        nombre TEXT,
        stock INTEGER,
        precio REAL,
        created_at TEXT
      )
    ''');
  }

  Future<List<Map<String, dynamic>>> getMateriales(String inventarioId) async {
    final db = await database;
    return db.query('materiales',
        where: 'inventario_id = ?',
        whereArgs: [inventarioId],
        orderBy: 'created_at DESC');
  }

  Future<void> insertMaterial(Map<String, dynamic> data) async {
    final db = await database;
    await db.insert('materiales', data,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteMaterial(String id) async {
    final db = await database;
    await db.delete('materiales', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateMaterial(String id, Map<String, dynamic> data) async {
    final db = await database;
    await db.update(
      'materiales',
      data,
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

// -------------------- INVENTORY SCREEN --------------------
class InventoryScreen extends StatefulWidget {
  final String usuario;
  final String codigo;

  const InventoryScreen(
      {super.key, required this.usuario, required this.codigo});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final dbHelper = DatabaseHelper.instance;
  List<Map<String, dynamic>> materiales = [];
  bool loading = true;

  int _selectedIndex = 0;

  final TextEditingController _nombreController = TextEditingController();
  final TextEditingController _stockController = TextEditingController();
  final TextEditingController _precioController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadLocal();
  }

  Future<void> _loadLocal() async {
    final data = await dbHelper.getMateriales(widget.codigo);
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
      'inventario_id': widget.codigo,
      'nombre': _nombreController.text,
      'stock': int.tryParse(_stockController.text) ?? 0,
      'precio': double.tryParse(_precioController.text) ?? 0.0,
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
            TextField(
                controller: _nombreController,
                decoration: const InputDecoration(labelText: 'Nombre')),
            TextField(
                controller: _stockController,
                decoration: const InputDecoration(labelText: 'Stock'),
                keyboardType: TextInputType.number),
            TextField(
                controller: _precioController,
                decoration: const InputDecoration(labelText: 'Precio'),
                keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
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
        content: TextField(
          controller: vendidoController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Cantidad Vendida'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              final vendido = int.tryParse(vendidoController.text) ?? 0;
              if (vendido > 0 && vendido <= mat['stock']) {
                final nuevoStock = mat['stock'] - vendido;
                await dbHelper.updateMaterial(mat['id'], {
                  'nombre': mat['nombre'],
                  'stock': nuevoStock,
                  'precio': mat['precio'],
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
            TextField(
                controller: _nombreController,
                decoration: const InputDecoration(labelText: 'Nombre')),
            TextField(
                controller: _stockController,
                decoration: const InputDecoration(labelText: 'Stock'),
                keyboardType: TextInputType.number),
            TextField(
                controller: _precioController,
                decoration: const InputDecoration(labelText: 'Precio'),
                keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          ElevatedButton(onPressed: _addMaterial, child: const Text('Guardar')),
        ],
      ),
    );
  }

  void _onNavTap(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Column(
        children: [
          // HEADER
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366f1), Color(0xFF8b5cf6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                )
              ],
            ),
            child: Column(
              children: [
                Text("Mi Inventario",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 5),
                Text("Gestiona tus productos fácilmente",
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14,
                    )),
              ],
            ),
          ),

          // CONTENIDO (IndexedStack)
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : IndexedStack(
                    index: _selectedIndex,
                    children: [
                      // INVENTARIO
                      ListView.builder(
                        padding: const EdgeInsets.all(20),
                        itemCount: materiales.length,
                        itemBuilder: (context, index) {
                          final mat = materiales[index];
                          return inventarioItem(mat);
                        },
                      ),

                      // ESTADÍSTICAS (solo ejemplo de barras)
                      ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          graficoBarras("📊 Productos Más Vendidos", {
                            for (var m in materiales)
                              m['nombre']: m['stock'] / (materiales.isEmpty ? 1 : materiales.map((e) => e['stock']).reduce((a, b) => a > b ? a : b))
                          }),
                        ],
                      ),

                      // HISTORIAL (placeholder, se puede mejorar)
                      ListView(
                        padding: const EdgeInsets.all(20),
                        children: const [
                          Text("Historial de movimientos (próximamente)"),
                        ],
                      ),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onNavTap,
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.grey[600],
        backgroundColor: Colors.white,
        elevation: 10,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.inventory_2), label: "Inventario"),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: "Stats"),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: "Historial"),
        ],
      ),
    );
  }

  Widget inventarioItem(Map<String, dynamic> mat) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Nombre + Acciones
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(mat['nombre'],
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87)),
              Row(
                children: [
                  actionBtn(Icons.edit, Colors.blue, () => _editMaterial(mat)),
                  const SizedBox(width: 8),
                  mat['stock'] > 0
                      ? actionBtn(Icons.shopping_cart, Colors.green,
                          () => _venderMaterial(mat))
                      : const Icon(Icons.warning, color: Colors.orange),
                  const SizedBox(width: 8),
                  actionBtn(Icons.delete, Colors.red,
                      () => _deleteMaterial(mat['id'])),
                ],
              )
            ],
          ),
          const SizedBox(height: 12),

          // Stock + Precio
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: mat['stock'] == 0
                      ? Colors.red
                      : mat['stock'] < 5
                          ? Colors.orange
                          : Colors.green,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text("Stock: ${mat['stock']}",
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 20),
              Text("Precio: \$${mat['precio']}",
                  style: const TextStyle(
                      color: Colors.grey, fontWeight: FontWeight.w500)),
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
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  Widget graficoBarras(String titulo, Map<String, double> data) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20
),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black87)),
          const SizedBox(height: 15),
          ...data.entries.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    SizedBox(
                        width: 80,
                        child: Text(e.key,
                            style: const TextStyle(color: Colors.grey))),
                    Expanded(
                      child: Stack(
                        children: [
                          Container(
                            height: 24,
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          FractionallySizedBox(
                            widthFactor: e.value,
                            child: Container(
                              height: 24,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                    colors: [Color(0xFF6366f1), Color(0xFF8b5cf6)]),
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text("${(e.value * 100).toInt()}",
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, color: Colors.black87)),
                  ],
                ),
              ))
        ],
      ),
    );
  }
}