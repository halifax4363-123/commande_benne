import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  // Force l'affichage en mode vertical (Portrait) uniquement
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const MyApp());
}

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
  
  // États de position de la benne pour verrouiller les boutons
  bool verinEtendu = false;
  bool verinRetracte = false;

  String statusMessage = "Déconnecté";
  String targetDeviceName = "HC-05";
  
  // Variables de télémétrie
  double tensionBatterie = 0.0;
  double puissanceVerin = 0.0;
  String bufferRecu = "";

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();
    _connectBluetooth();
  }

  Future<void> _connectBluetooth() async {
    setState(() {
      statusMessage = "Recherche du module...";
    });
    try {
      List<BluetoothDevice> bondedDevices = await FlutterBluetoothSerial.instance.getBondedDevices();
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
          // Au démarrage, autorise les deux mouvements dans le doute
          verinEtendu = false;
          verinRetracte = false;
        });

        // Écoute active et décodage des retours Arduino
        connection!.input!.listen(_onDataReceived).onDone(() {
          setState(() {
            isConnected = false;
            statusMessage = "Déconnecté";
          });
        });
      } else {
        setState(() {
          statusMessage = "Bluetooth non appairé dans Android";
        });
      }
    } catch (e) {
      setState(() {
        isConnected = false;
        statusMessage = "Échec de la connexion";
      });
    }
  }

  // Traitement des messages texte reçus de l'Arduino
  void _onDataReceived(Uint8List data) {
    bufferRecu += utf8.decode(data);
    
    // Découpage par ligne (\n)
    while (bufferRecu.contains('\n')) {
      int indexFin = bufferRecu.indexOf('\n');
      String ligne = bufferRecu.substring(0, indexFin).trim();
      bufferRecu = bufferRecu.substring(indexFin + 1);

      if (ligne.startsWith("DATA:")) {
        // Traitement de la télémétrie "DATA:Tension,Puissance"
        List<String> valeurs = ligne.substring(5).split(',');
        if (valeurs.length >= 2) {
          setState(() {
            tensionBatterie = double.tryParse(valeurs[0]) ?? 0.0;
            puissanceVerin = double.tryParse(valeurs[1]) ?? 0.0;
          });
        }
      } else if (ligne.startsWith("STAT:")) {
        // Traitement des retours de fin de course mécanique
        String statut = ligne.substring(5);
        setState(() {
          if (statut == "HAUT") {
            verinEtendu = true;
            verinRetracte = false;
            isMoving = false;
            statusMessage = "Prêt (Benne Haute)";
          } else if (statut == "BAS") {
            verinEtendu = false;
            verinRetracte = true;
            isMoving = false;
            statusMessage = "Prêt (Benne Basse)";
          } else if (statut == "FIN_ALERTE") {
            isMoving = false;
            statusMessage = "Prêt";
          }
        });
      }
    }
  }

  void _sendOrder(String character, int blockDurationSeconds, String actionText) async {
    if (connection != null && isConnected) {
      connection!.output.add(ascii.encode(character));
      await connection!.output.allSent;
      setState(() {
        isMoving = true;
        statusMessage = actionText;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Condition pour griser ou activer dynamiquement les boutons
    bool boutonMonterActif = isConnected && !isMoving && !verinEtendu;
    bool boutonDescendreActif = isConnected && !isMoving && !verinRetracte;
    bool boutonAlerteActif = isConnected && !isMoving;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Commande de benne', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF10288C),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Mention textuelle demandée au-dessus de la connexion
            const Text(
              'Classe Electro-Méca 1B - 2026',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.grey),
            ),

            // Indicateur de connexion avec pastille colorée
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: isConnected ? const Color(0xFF00FFD2) : const Color(0xFFFF141A),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Text(
                    statusMessage,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!isConnected)
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _connectBluetooth,
                  ),
              ],
            ),

            // Boutons Monter et Descendre côte à côte (hauteur 70)
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 70,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10288C),
                        disabledBackgroundColor: const Color(0xFFCBE2FE),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                      onPressed: boutonMonterActif
                          ? () => _sendOrder('M', 12, "Montée en cours (12s)...")
                          : null,
                      child: const Text('Monter', style: TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: SizedBox(
                    height: 70,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF8014),
                        disabledBackgroundColor: const Color(0xFFFFD863),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      ),
                      onPressed: boutonDescendreActif
                          ? () => _sendOrder('D', 12, "Descente en cours (12s)...")
                          : null,
                      child: const Text('Descendre', style: TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ],
            ),

            // Bouton Test Alerte aligné sur la gauche
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isMoving && statusMessage.contains("Alerte") ? const Color(0xFFFF45DD) : const Color(0xFFFFCAEA),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  onPressed: boutonAlerteActif
                      ? () => _sendOrder('A', 3, "Alerte ! (3s)")
                      : null,
                  child: Text(
                    isMoving && statusMessage.contains("Alerte") ? 'Alerte !' : 'Test Alerte',
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF10288C),
                      fontWeight: FontWeight.bold,
                    ),
                  ), // 1. Ferme TextStyle, 2. Ferme Text
                ), // 3. Ferme ElevatedButton
              ), // 4. Ferme SizedBox
            ), // Ferme Align
		

            // Zone d'affichage des capteurs de télémétrie
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              child: Padding(
				padding: const EdgeInsets.all(15.0),
				child: Column(
				children: [
				Row(
				mainAxisAlignment: MainAxisAlignment.spaceBetween,
				children: [
				const Text("Tension de batterie (min. 10v) :", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
				Text("${tensionBatterie.toStringAsFixed(1)} V", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: tensionBatterie < 10.0 ? Colors.red : Colors.green)),
				],
				),
				const Divider(height: 20),
				Row(
				mainAxisAlignment: MainAxisAlignment.spaceBetween,
				children: [
				const Text("Conso. vérin :", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
				Text("${puissanceVerin.toStringAsFixed(1)} W", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF10288C))),
				],
			),
		],
	),
),
),
],
),
),
);
}
}
