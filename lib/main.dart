import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p; // Alias para evitar choque con BuildContext
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Inventario (${widget.usuario})')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : materiales.isEmpty
              ? const Center(child: Text("No hay materiales"))
              : ListView.builder(
                  itemCount: materiales.length,
                  itemBuilder: (context, index) {
                    final mat = materiales[index];
                    return Container(
                      color: mat['stock'] == 0
                          ? Colors.grey[200]
                          : Colors.transparent,
                      child: ListTile(
                        title: Text(mat['nombre']),
                        subtitle: Row(
                          children: [
                            Text(
                              "Stock: ${mat['stock']}",
                              style: TextStyle(
                                color: mat['stock'] == 0
                                    ? Colors.red
                                    : Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text("Precio: ${mat['precio']}"),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () => _editMaterial(mat),
                            ),
                            mat['stock'] > 0
                                ? IconButton(
                                    icon: const Icon(Icons.shopping_cart,
                                        color: Colors.green),
                                    onPressed: () => _venderMaterial(mat),
                                  )
                                : const Icon(Icons.warning,
                                    color: Colors.orange),
                            IconButton(
                              icon:
                                  const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteMaterial(mat['id']),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}