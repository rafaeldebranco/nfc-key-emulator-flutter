import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:nfc_host_card_emulation/nfc_host_card_emulation.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Inicializa o HCE com o AID configurado no AndroidManifest.xml
  // F0010203040506 em bytes: [0xF0, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06]
  try {
    await NfcHce.init(
      aid: Uint8List.fromList([0xF0, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06]),
      permanentApduResponses: true,
      listenOnlyConfiguredPorts: false,
    );
  } catch (e) {
    debugPrint("HCE init error: $e");
  }

  runApp(const NFCKeyApp());
}

class NFCKeyApp extends StatelessWidget {
  const NFCKeyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NFC Key App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _tagController = TextEditingController();
  List<String> _savedKeys = [];
  bool _isReading = false;
  bool _isTransmitting = false;
  String? _activeKey;

  @override
  void initState() {
    super.initState();
    _loadSavedKeys();
  }

  Future<void> _loadSavedKeys() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _savedKeys = prefs.getStringList('saved_keys') ?? [];
    });
  }

  Future<void> _saveKey(String key) async {
    if (key.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    if (!_savedKeys.contains(key)) {
      _savedKeys.add(key);
      await prefs.setStringList('saved_keys', _savedKeys);
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chave salva com sucesso!')),
      );
    }
  }

  Future<void> _deleteKey(int index) async {
    final prefs = await SharedPreferences.getInstance();
    String keyToDelete = _savedKeys[index];
    _savedKeys.removeAt(index);
    await prefs.setStringList('saved_keys', _savedKeys);
    
    if (_activeKey == keyToDelete) {
      _isTransmitting = false;
      _activeKey = null;
    }
    
    setState(() {});
  }

  Future<void> _readNFCTag() async {
    setState(() => _isReading = true);
    try {
      var availability = await FlutterNfcKit.nfcAvailability;
      if (availability != NFCAvailability.available) {
        throw 'NFC não disponível ou desativado no dispositivo.';
      }

      var tag = await FlutterNfcKit.poll(
        timeout: const Duration(seconds: 15),
        iosAlertMessage: "Aproxime a tag NFC da parte traseira do celular",
      );

      if (!mounted) return;
      setState(() {
        _tagController.text = tag.id;
      });

      await FlutterNfcKit.finish();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tag lida com sucesso!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isReading = false);
      }
    }
  }

  Future<void> _toggleTransmission(String keyData) async {
    if (_isTransmitting && _activeKey == keyData) {
      try {
        await NfcHce.removeApduResponse(0); // Remove a resposta do "porto" 0
        setState(() {
          _isTransmitting = false;
          _activeKey = null;
        });
      } catch (e) {
        debugPrint("Error stopping HCE: $e");
      }
    } else {
      try {
        // Converte a string da chave em bytes para responder ao leitor
        List<int> keyBytes = keyData.codeUnits;
        await NfcHce.addApduResponse(0, keyBytes);
        
        if (!mounted) return;
        setState(() {
          _isTransmitting = true;
          _activeKey = keyData;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Transmitindo chave: $keyData')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao ativar transmissor: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NFC Key Emulator'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    TextField(
                      controller: _tagController,
                      decoration: const InputDecoration(
                        labelText: 'Código da Tag (ID)',
                        hintText: 'Leia uma tag ou digite manualmente',
                        prefixIcon: Icon(Icons.vpn_key_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _isReading ? null : _readNFCTag,
                            icon: _isReading 
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.nfc),
                            label: Text(_isReading ? 'Lendo...' : 'Ler Tag'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _saveKey(_tagController.text),
                            icon: const Icon(Icons.add),
                            label: const Text('Adicionar'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Icon(Icons.list, size: 20),
                SizedBox(width: 8),
                Text(
                  'Chaves Salvas',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const Divider(indent: 16, endIndent: 16),
          Expanded(
            child: _savedKeys.isEmpty
                ? const Center(child: Text('Nenhuma chave cadastrada.'))
                : ListView.builder(
                    itemCount: _savedKeys.length,
                    itemBuilder: (context, index) {
                      final key = _savedKeys[index];
                      final isActive = _isTransmitting && _activeKey == key;
                      
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isActive ? Colors.green : Colors.grey.shade200,
                          child: Icon(
                            isActive ? Icons.sensors : Icons.key,
                            color: isActive ? Colors.white : Colors.grey,
                          ),
                        ),
                        title: Text(key, style: const TextStyle(fontWeight: FontWeight.w500)),
                        subtitle: Text(isActive ? 'Transmitindo...' : 'Toque para usar como chave'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(
                                isActive ? Icons.stop_circle : Icons.play_circle_fill,
                                color: isActive ? Colors.red : Colors.green,
                                size: 32,
                              ),
                              onPressed: () => _toggleTransmission(key),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _deleteKey(index),
                            ),
                          ],
                        ),
                        onTap: () {
                          setState(() => _tagController.text = key);
                        },
                      );
                    },
                  ),
          ),
          if (_isTransmitting)
            Container(
              width: double.infinity,
              color: Colors.green.shade700,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.sensors, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'MODO CHAVE ATIVO: $_activeKey',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _toggleTransmission(_activeKey!),
                    child: const Text('PARAR', style: TextStyle(color: Colors.white, decoration: TextDecoration.underline)),
                  )
                ],
              ),
            ),
        ],
      ),
    );
  }
}
