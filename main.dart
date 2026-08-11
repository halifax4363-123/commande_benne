import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Commande Benne',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const RemoteScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class RemoteScreen extends StatefulWidget {
  const RemoteScreen({Key? key}) : super(key: key);
  @override
  _RemoteScreenState createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen> {
  BluetoothConnection? connection;
  bool isConnected = false;
  bool isMoving = false;
  String statusMessage = "Déconnecté";
  String targetDeviceName = "HC-05"; // Nom de votre module Bluetooth

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  // Demande les droits Bluetooth requis par Android
  Future<void> _requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();
    _connectBluetooth();
  }

  // Connexion automatique au HC-05
  Future<void> _connectBluetooth() async {
    setState(() {
      statusMessage = "Recherche du module...";
    });
    try {
      List<BluetoothDevice> bondedDevices = await FlutterBluetoothSerial
          .instance
          .getBondedDevices();
      BluetoothDevice? targetDevice;

      for (var device in bondedDevices) {
        if (device.name == targetDeviceName) {
          targetDevice = device;
          break;
        }
      }

      if (targetDevice != null) {
        setState(() {
          statusMessage = "Connexion à ${targetDevice!.name}...";
        });
        connection = await BluetoothConnection.toAddress(targetDevice.address);
        setState(() {
          isConnected = true;
          statusMessage = "Connecté à ${targetDevice!.name}";
        });

        // Écoute les données reçues de l'Arduino (Tension de batterie future)
        connection!.input!
            .listen((data) {
              // Logique future pour lire la tension batterie
            })
            .onDone(() {
              setState(() {
                isConnected = false;
                statusMessage = "Déconnecté";
              });
            });
      } else {
        setState(() {
          statusMessage = "Module HC-05 non appairé dans Android";
        });
      }
    } catch (e) {
      setState(() {
        isConnected = false;
        statusMessage = "Échec de la connexion";
      });
    }
  }

  // Envoi des ordres à l'Arduino avec gestion de temporisation
  void _sendOrder(
    String character,
    int blockDurationSeconds,
    String actionText,
  ) async {
    if (connection != null && isConnected) {
      connection!.output.add(ascii.encode(character));
      await connection!.output.allSent;

      setState(() {
        isMoving = true;
        statusMessage = actionText;
      });

      // Bloque l'interface pendant la durée de l'action (12s ou 10s)
      await Future.delayed(Duration(seconds: blockDurationSeconds));

      setState(() {
        isMoving = false;
        statusMessage = "Prêt";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text(
          'Commande de benne automatique',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF10288C),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Indicateur de connexion avec pastille colorée
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: isConnected
                        ? const Color(0xFF00FFD2)
                        : const Color(0xFFFF141A),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 15),
                Text(
                  statusMessage,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (!isConnected) ...[
                  const SizedBox(width: 10),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _connectBluetooth,
                  ),
                ],
              ],
            ),

            // Boutons Monter et Descendre côte à côte
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 120,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10288C),
                        disabledBackgroundColor: const Color(0xFFCBE2FE),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      onPressed: (isConnected && !isMoving)
                          ? () =>
                                _sendOrder('M', 12, "Montée en cours (12s)...")
                          : null,
                      child: const Text(
                        'MONTER',
                        style: TextStyle(
                          fontSize: 22,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: SizedBox(
                    height: 120,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF8014),
                        disabledBackgroundColor: const Color(0xFFFFD863),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      onPressed: (isConnected && !isMoving)
                          ? () => _sendOrder(
                              'D',
                              10,
                              "Descente en cours (10s)...",
                            )
                          : null,
                      child: const Text(
                        'DESCENDRE',
                        style: TextStyle(
                          fontSize: 22,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Bouton Test Alerte centré en bas
            SizedBox(
              width: double.infinity,
              height: 70,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFCAEA),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                onPressed: (isConnected && !isMoving)
                    ? () => _sendOrder('A', 2, "Alerte envoyée")
                    : null,
                child: const Text(
                  'TEST ALERTE',
                  style: TextStyle(
                    fontSize: 18,
                    color: Color(0xFF10288C),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
