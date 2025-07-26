import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Crane Scale Reader',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const ScaleReaderScreen(),
    );
  }
}

class ScaleReaderScreen extends StatefulWidget {
  const ScaleReaderScreen({super.key});

  @override
  State<ScaleReaderScreen> createState() => _ScaleReaderScreenState();
}

class _ScaleReaderScreenState extends State<ScaleReaderScreen> {
  final String targetDeviceName = 'IF_B7';
  final String targetDeviceAddress = '2A:C0:19:11:25:65';
  String _weight = '0.00';
  double _maxWeight = 0.0;
  double _upperLimit = 100.0;
  double _threshold = 5.0;
  bool _isScanning = false;
  bool _isTimerRunning = false;
  int _timerSeconds = 0;
  late Timer _timer;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  final TextEditingController _thresholdDialogController = TextEditingController();
  final TextEditingController _limitDialogController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  @override
  void dispose() {
    _stopScan();
    _thresholdDialogController.dispose();
    _limitDialogController.dispose();
    _stopTimer();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    await Permission.bluetooth.request();
    await Permission.bluetoothConnect.request();
    await Permission.bluetoothScan.request();
    await Permission.location.request();
  }

  void _startScan() {
    if (_isScanning) return;

    setState(() {
      _isScanning = true;
      _weight = '0.00';
    });

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult result in results) {
        if (result.device.remoteId.str == targetDeviceAddress ||
            result.device.advName == targetDeviceName) {
          _processAdvertisementData(result.advertisementData);
        }
      }
    }, onError: (e) {
      print('Error scanning: $e');
    });

    FlutterBluePlus.startScan(
      timeout: const Duration(days: 1),
      androidUsesFineLocation: false,
    );
  }

  void _stopScan() {
    if (!_isScanning) return;

    _scanSubscription?.cancel();
    FlutterBluePlus.stopScan();
    setState(() {
      _isScanning = false;
    });
  }

  void _processAdvertisementData(AdvertisementData advertisementData) {
    final manufacturerData = advertisementData.manufacturerData;
    if (manufacturerData.isEmpty) return;

    final data = manufacturerData.values.first;
    final hexString = data.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

    try {
      final splitIndex = hexString.indexOf('01f4');
      if (splitIndex == -1) return;

      final weightHex = hexString.substring(splitIndex - 4, splitIndex);
      final weight = int.parse(weightHex, radix: 16);
      final weightKg = weight / 100;

      setState(() {
        _weight = weightKg.toStringAsFixed(2);
        if (weightKg > _maxWeight) {
          _maxWeight = weightKg;
        }

        if (weightKg > _threshold) {
          if (!_isTimerRunning) {
            _startTimer();
          }
        } else {
          if (_isTimerRunning) {
            _stopTimer();
          }
        }
      });
    } catch (e) {
      print('Error parsing weight: $e');
    }
  }

  void _startTimer() {
    setState(() {
      _isTimerRunning = true;
      _timerSeconds = 0;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _timerSeconds++;
      });
    });
  }

  void _stopTimer() {
    _timer.cancel();
    setState(() {
      _isTimerRunning = false;
      _timerSeconds = 0;
    });
  }

  void _resetMaxWeight() {
    setState(() {
      _maxWeight = 0.0;
    });
  }

  Future<void> _showThresholdDialog() async {
    _thresholdDialogController.text = _threshold.toString();
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Set Threshold'),
          content: TextField(
            controller: _thresholdDialogController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Weight threshold (kg)',
              border: OutlineInputBorder(),
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Save'),
              onPressed: () {
                final newThreshold = double.tryParse(_thresholdDialogController.text) ?? _threshold;
                setState(() {
                  _threshold = newThreshold > 0 ? newThreshold : 10.0;
                });
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _showUpperLimitDialog() async {
    _limitDialogController.text = _upperLimit.toString();
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Set Upper Limit'),
          content: TextField(
            controller: _limitDialogController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Maximum weight (kg)',
              border: OutlineInputBorder(),
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Save'),
              onPressed: () {
                final newLimit = double.tryParse(_limitDialogController.text) ?? _upperLimit;
                setState(() {
                  _upperLimit = newLimit > 0 ? newLimit : 150.0;
                });
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  String _formatTime(int seconds) {
    final minutes = (seconds / 60).floor();
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    double currentWeight = double.tryParse(_weight) ?? 0.0;
    double percentage = (currentWeight / _upperLimit).clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Crane Scale Reader'),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Current Weight Display
                const Text(
                  'Current Weight:',
                  style: TextStyle(fontSize: 24),
                ),
                Text(
                  '$_weight kg',
                  style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),

                // Timer Display
                GestureDetector(
                  onTap: _showThresholdDialog,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: _isTimerRunning ? Colors.green : Colors.grey),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'Duration Above Threshold',
                          style: TextStyle(fontSize: 18),
                        ),
                        Text(
                          'Threshold: ${_threshold.toStringAsFixed(1)} kg',
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _formatTime(_timerSeconds),
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: _isTimerRunning ? Colors.green : Colors.black,
                          ),
                        ),
                        Text(
                          _isTimerRunning ? 'Timer is running' : 'Timer stopped',
                          style: TextStyle(
                            color: _isTimerRunning ? Colors.green : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Max Weight Display (now clickable to reset)
                GestureDetector(
                  onTap: _resetMaxWeight,
                  child: Column(
                    children: [
                      const Text(
                        'Max Weight:',
                        style: TextStyle(fontSize: 20),
                      ),
                      Text(
                        '${_maxWeight.toStringAsFixed(2)} kg',
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue, // Add color to indicate clickable
                        ),
                      ),
                      const Text(
                        '(Tap to reset)',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),

                // Visual Magnitude Meter
                GestureDetector(
                  onTap: _showUpperLimitDialog,
                  child: Column(
                    children: [
                      const Text(
                        'Weight Meter (Tap to set max)',
                        style: TextStyle(fontSize: 18),
                      ),
                      Text(
                        'Max: ${_upperLimit.toStringAsFixed(0)} kg',
                        style: const TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: MediaQuery.of(context).size.width * 0.9,
                        height: 50,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: Stack(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(25),
                                gradient: const LinearGradient(
                                  colors: [
                                    Colors.green,
                                    Colors.yellow,
                                    Colors.red,
                                  ],
                                  stops: [0.0, 0.7, 1.0],
                                ),
                              ),
                            ),
                            FractionallySizedBox(
                              widthFactor: percentage,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(25),
                                ),
                              ),
                            ),
                            Center(
                              child: Text(
                                '${(percentage * 100).toStringAsFixed(0)}% (${currentWeight.toStringAsFixed(1)} kg)',
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '0 kg',
                            style: TextStyle(fontSize: 12),
                          ),
                          Text(
                            '${_upperLimit.toStringAsFixed(0)} kg',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),

                // Scan Button
                ElevatedButton(
                  onPressed: _isScanning ? _stopScan : _startScan,
                  child: Text(_isScanning ? 'Stop Scanning' : 'Start Scanning'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}